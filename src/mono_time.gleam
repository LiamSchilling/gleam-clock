//// A monadic type abstraction for access to validated monotonic timestamps.

import gleam/order
import gleam/time/timestamp.{type Timestamp}

//------------------------------------------------------------------------------
// User-facing
//------------------------------------------------------------------------------

/// A monad providing access to timestamps that are validated for monotonicity
/// at every retrieval.
pub opaque type MonoTime(a) {
  MonoTime(out: fn(fn() -> Timestamp, State) -> #(a, State))
}

/// The type of monotonic time exceptions.
pub type MonoTimeException {
  ObservedNonmonotonicTime(count: Int)
}

/// Inject a value into the monadic context.
pub fn pure(value: a) -> MonoTime(a) {
  use _, state <- MonoTime
  #(value, state)
}

/// Map a monadic value along the designated callback.
pub fn map(thunk: MonoTime(a), callback: fn(a) -> b) -> MonoTime(b) {
  use current_time, state <- MonoTime
  let #(value, state) = thunk.out(current_time, state)
  #(callback(value), state)
}

/// Force a monadic value, then continue with the designated callback.
pub fn bind(thunk: MonoTime(a), callback: fn(a) -> MonoTime(b)) -> MonoTime(b) {
  use current_time, state <- MonoTime
  let #(value, state) = thunk.out(current_time, state)
  callback(value).out(current_time, state)
}

/// Access the current timestamp in the monadic context, or return an error.
pub fn get() -> MonoTime(Result(Timestamp, MonoTimeException)) {
  use current_time, state <- MonoTime
  step(state, current_time())
}

/// Force a monadic value using a specified function to retrieve timestamps.
pub fn run(thunk: MonoTime(a), current_time: fn() -> Timestamp) -> a {
  let #(value, _) = thunk.out(current_time, Init)
  value
}

//------------------------------------------------------------------------------
// Internals
//------------------------------------------------------------------------------

/// The internal state tracking timestamps.
type State {
  Init
  Track(prev: Timestamp)
  Except(count: Int)
}

/// The result type of stepping a state by one timestamp.
type Step =
  #(Result(Timestamp, MonoTimeException), State)

/// The result of a successful step.
fn step_ok(time: Timestamp) -> Step {
  #(Ok(time), Track(time))
}

/// The result of an erroneous step.
fn step_error(count: Int) -> Step {
  #(Error(ObservedNonmonotonicTime(count)), Except(count))
}

/// Step a state by one observed timestamp.
fn step(state: State, time: Timestamp) -> Step {
  case state {
    Init -> step_ok(time)

    Track(prev) -> {
      case timestamp.compare(prev, time) {
        order.Gt -> step_error(1)
        _ -> step_ok(time)
      }
    }

    Except(count) -> step_error(count + 1)
  }
}
