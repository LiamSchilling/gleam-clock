//// A monad that provides query access to validated monotonic timestamps.
//// 
//// Monotonicity means that time may not decrease between queries, so the timer
//// may not "run backward". This is enforced by returning only error values
//// after any decreasing timestamp is detected.

import gleam/order
import gleam/time/timestamp.{type Timestamp}

/// A computation provided query access to timestamps that are validated for
/// monotonicity.
pub opaque type MonoTime(a) {
  MonoTime(out: fn(fn() -> Timestamp, State) -> #(a, State))
}

/// A monotonicity exception, which includes a count of how many erroneous
/// queries have been made so far.
pub type MonoTimeException {
  ObservedDecreasingTimestamp(count: Int)
}

/// Inject a value into the monadic context.
pub fn pure(value: a) -> MonoTime(a) {
  use _, state <- MonoTime
  #(value, state)
}

/// Map a value within the monadic context.
pub fn map(thunk: MonoTime(a), callback: fn(a) -> b) -> MonoTime(b) {
  use timer, state <- MonoTime
  let #(value, state) = thunk.out(timer, state)
  #(callback(value), state)
}

/// Run the monadic computation, then continue with the callback.
pub fn bind(thunk: MonoTime(a), callback: fn(a) -> MonoTime(b)) -> MonoTime(b) {
  use timer, state <- MonoTime
  let #(value, state) = thunk.out(timer, state)
  callback(value).out(timer, state)
}

/// Query the current timestamp as a monadic computation. If the internal timer
/// produces a decreasing timestamp, then an error value is returned and the
/// timer is deactivated, so that any further queries will also return an error
/// value.
/// 
/// When a monadic computation is run, the first query is guaranteed to
/// succeed.
pub fn get() -> MonoTime(Result(Timestamp, MonoTimeException)) {
  use timer, state <- MonoTime
  step(state, timer())
}

/// Run the monadic computation. The caller must provide a timer, which is
/// called on each query to retrieve the desired timestamp.
pub fn run(thunk: MonoTime(a), timer: fn() -> Timestamp) -> a {
  let #(value, _) = thunk.out(timer, Init)
  value
}

type State {
  Init
  Track(prev: Timestamp)
  Except(count: Int)
}

type Step =
  #(Result(Timestamp, MonoTimeException), State)

fn step_as_ok(time: Timestamp) -> Step {
  #(Ok(time), Track(time))
}

fn step_as_error(count: Int) -> Step {
  #(Error(ObservedDecreasingTimestamp(count)), Except(count))
}

fn step(state: State, time: Timestamp) -> Step {
  case state {
    Init -> step_as_ok(time)

    Track(prev) -> {
      case timestamp.compare(prev, time) {
        order.Gt -> step_as_error(1)
        _ -> step_as_ok(time)
      }
    }

    Except(count) -> step_as_error(count + 1)
  }
}
