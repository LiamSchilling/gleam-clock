//// A clock server that emits a "tick" at regular time intervals.
//// 
//// The tick message includes timestamp information for precise real-time
//// simulations. The internal timer is validated for monotonicity, which may
//// fail, at which point an error value is emitted and the clock server is
//// terminated.
//// 
//// Settings such as frame rate and internal time scale may be adjusted. The
//// clock may be paused and resumed via external messages.
//// 
//// Internally, each tick is scheduled in advance according to the desired
//// frame rate, and the scheduling of a tick is never undone or modified. The
//// effect of this is that changes to the configuration of a running clock do
//// not take effect until the scheduling of the next tick, which is usually
//// once the currently-scheduled tick fires.

import gleam/erlang/process.{type Subject}
import gleam/float
import gleam/result
import gleam/time/duration
import gleam/time/timestamp.{type Timestamp}
import mono_time.{type MonoTime, type MonoTimeException}

const millis_per_second = 1000.0

/// A configuration of the timing settings of the clock, including frame rate
/// and internal time scaling.
pub opaque type Config {
  Config(ticks_per_unit: Float, units_per_second: Float)
}

/// A configuration creation exception.
pub type ConfigException {
  TicksPerUnitNonPositive
  UnitsPerSecondNonPositive
  BothNonPositive
}

/// Construct and return a validated configuration. An error value is returned
/// if either argument is non-positive.
pub fn new_config(
  ticks_per_unit: Float,
  units_per_second: Float,
) -> Result(Config, ConfigException) {
  case ticks_per_unit <=. 0.0, units_per_second <=. 0.0 {
    False, False -> Ok(Config(ticks_per_unit:, units_per_second:))
    False, True -> Error(UnitsPerSecondNonPositive)
    True, False -> Error(TicksPerUnitNonPositive)
    True, True -> Error(BothNonPositive)
  }
}

/// A potential client of the clock, which must provide a handler for tick
/// messages and a handler for error messages.
pub opaque type Client {
  Client(on_tick: fn(Tick) -> Nil, on_error: fn(MonoTimeException) -> Nil)
}

/// Construct and return a client identifier.
pub fn new_client(
  on_tick: fn(Tick) -> Nil,
  on_error: fn(MonoTimeException) -> Nil,
) -> Client {
  Client(on_tick:, on_error:)
}

/// A tick message, which provides timestamp information.
pub opaque type Tick {
  Tick(delta_time: Float)
}

/// From a tick message, retrieve the units of time elapsed since the previous
/// tick.
pub fn delta_time(tick: Tick) -> Float {
  tick.delta_time
}

/// A running state of the clock.
pub type State {
  /// The clock is running normally.
  Resume
  /// The clock is paused. No ticks are emitted and elapsed time is disregarded.
  Pause
}

/// A clock identifier.
pub opaque type Clock {
  Clock(subject: Subject(Message))
}

/// Initialize and return a new clock in the paused state. The caller must
/// provide the internal timer.
pub fn new(
  config: Config,
  client: Client,
  current_time: fn() -> Timestamp,
) -> Clock {
  let reply = process.new_subject()

  process.spawn(fn() {
    mono_time.run(
      {
        use maybe_clock <- mono_time.bind(new_clock(config, client))
        case maybe_clock {
          Ok(clock) -> {
            process.send(reply, clock.subject)
            loop_clock(clock)
          }

          Error(_) -> {
            panic as "Impossible: First query to a monotonic timer failed"
          }
        }
      },
      current_time,
    )
  })

  Clock(process.receive_forever(reply))
}

/// Set the configuration of the clock. The updated configuration takes effect
/// on the scheduling of the next tick, and does not effect the timing of a
/// currently-scheduled tick.
pub fn set_config(clock: Clock, config: Config) -> Nil {
  process.send(clock.subject, SetConfig(config))
}

/// Set the running state of the clock.
/// 
/// A resume schedules the next tick immediately, if there is not one already
/// scheduled.
/// 
/// A pause takes effect immediately, so that any currently-scheduled tick is
/// ignored once it fires, and no message will be emitted by the clock. A pause
/// does not get rid of the currently-scheduled tick, which would still fire
/// properly if the clock were then immediately resumed.
pub fn set_state(clock: Clock, state: State) -> Nil {
  process.send(clock.subject, SetState(state))
}

/// Terminate the clock and free its resources. It is technically safe to send
/// messages to a terminated clock, but they will be ignored.
pub fn shutdown(clock: Clock) -> Nil {
  process.send(clock.subject, Shutdown)
}

type Message {
  SetConfig(config: Config)
  SetState(state: State)
  EmitTick
  Shutdown
}

type InternalState {
  ResumeTicking
  PauseTicking
  PauseSilent
}

fn revise_state(internal_state: InternalState, state: State) -> InternalState {
  case internal_state, state {
    _, Resume -> ResumeTicking
    ResumeTicking, Pause -> PauseTicking
    p, Pause -> p
  }
}

type InternalClock {
  InternalClock(
    subject: Subject(Message),
    config: Config,
    client: Client,
    state: InternalState,
    time: Timestamp,
  )
}

fn new_clock(
  config: Config,
  client: Client,
) -> MonoTime(Result(InternalClock, MonoTimeException)) {
  use maybe_time <- mono_time.map(mono_time.get())
  use time <- result.map(maybe_time)
  InternalClock(
    subject: process.new_subject(),
    config:,
    client:,
    state: PauseSilent,
    time:,
  )
}

fn emit_tick(clock: InternalClock, time: Timestamp) -> Nil {
  clock.client.on_tick(calc_delta_time(clock.time, time, clock.config))
}

fn emit_error(clock: InternalClock, err: MonoTimeException) -> Nil {
  clock.client.on_error(err)
}

fn queue_tick(
  clock: InternalClock,
  continuation: fn(Timestamp) -> MonoTime(Nil),
) -> MonoTime(Nil) {
  use maybe_time <- mono_time.bind(mono_time.get())
  case maybe_time {
    Ok(time) -> {
      process.send_after(
        clock.subject,
        calc_target_delay(clock.config),
        EmitTick,
      )

      continuation(time)
    }

    Error(err) -> {
      mono_time.pure(emit_error(clock, err))
    }
  }
}

fn loop_clock(clock: InternalClock) -> MonoTime(Nil) {
  case process.receive_forever(clock.subject) {
    SetConfig(config) -> {
      loop_clock(InternalClock(..clock, config:))
    }

    SetState(state) -> {
      use time <-
        case clock.state, state {
          PauseSilent, Resume -> queue_tick(clock, _)
          _, _ -> continue_with(clock.time, _)
        }

      loop_clock(
        InternalClock(..clock, time:, state: revise_state(clock.state, state)),
      )
    }

    EmitTick -> {
      case clock.state {
        ResumeTicking -> {
          use time <- queue_tick(clock)
          emit_tick(clock, time)
          loop_clock(InternalClock(..clock, time:))
        }

        PauseTicking -> {
          loop_clock(InternalClock(..clock, state: PauseSilent))
        }

        PauseSilent -> {
          panic as "Impossible: Silent clock received a tick"
        }
      }
    }

    Shutdown -> {
      mono_time.pure(Nil)
    }
  }
}

fn calc_target_delay(config: Config) -> Int {
  float.round(
    millis_per_second /. { config.ticks_per_unit *. config.units_per_second },
  )
}

fn calc_delta_time(left: Timestamp, right: Timestamp, config: Config) -> Tick {
  Tick(
    config.units_per_second
    *. duration.to_seconds(timestamp.difference(left, right)),
  )
}

fn continue_with(value: a, continuation: fn(a) -> b) -> b {
  continuation(value)
}
