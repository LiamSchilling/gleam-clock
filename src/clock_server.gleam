//// A clock process that emits a "tick" at regular time intervals. The tick
//// message includes timestamp information for precise real-time simulations.
//// Settings such as the frame rate and internal time scale may be customized.
//// The clock may be paused and resumed by way of external messaging.

import gleam/erlang/process.{type Subject}
import gleam/float
import gleam/result
import gleam/time/duration
import gleam/time/timestamp.{type Timestamp}
import mono_time.{type MonoTime, type MonoTimeException}

const millis_per_second = 1000.0

/// The data that specifies the behavior of the clock, and should be determined
/// at initialization.
pub opaque type Config {
  Config(ticks_per_unit: Float, units_per_second: Float)
}

/// The type of configuration creation exceptions.
pub type ConfigException {
  TicksPerUnitNonPositive
  UnitsPerSecondNonPositive
  BothNonPositive
}

/// Construct and return a validated configuration, or return an error.
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

/// The type of potential clock clients, which must provide callbacks to handle
/// various events.
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

/// The message emitted by the clock per tick.
pub opaque type Tick {
  Tick(delta_time: Float)
}

/// Retrieve the units of time elapsed since the previous tick.
pub fn delta_time(tick: Tick) -> Float {
  tick.delta_time
}

/// The running state of the clock.
pub type State {
  Resume
  Pause
}

/// The abstract type of clock identifiers.
pub opaque type Clock {
  Clock(subject: Subject(Message))
}

/// Initialize and return a new clock in the paused state.
pub fn new(
  config: Config,
  client: Client,
  current_time: fn() -> Timestamp,
) -> Clock {
  let reply = process.new_subject()

  process.spawn(fn() {
    mono_time.run(
      {
        use maybe_clock <- mono_time.bind(new_internal(config, client))
        case maybe_clock {
          Ok(clock) -> {
            process.send(reply, clock.subject)
            loop_internal(clock)
          }

          Error(_) -> {
            panic as "Impossible: First access to a monotonic timer failed"
          }
        }
      },
      current_time,
    )
  })

  Clock(process.receive_forever(reply))
}

/// Set the configuration of the clock. The updated configuration takes effect
/// after the next tick is emitted.
pub fn set_config(clock: Clock, config: Config) -> Nil {
  process.send(clock.subject, SetConfig(config))
}

/// Set the running state of the clock. A resume schedules the next tick
/// immediately, if there is not one already scheduled. A pause takes effect
/// immediately, so that the previously scheduled tick is ignored, and no
/// message will be emitted. A pause does NOT undo the scheduling of that
/// previously scheduled tick.
pub fn set_state(clock: Clock, state: State) -> Nil {
  process.send(clock.subject, SetState(state))
}

/// Terminate the clock and free its resources.
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

fn new_internal(
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

fn loop_internal(clock: InternalClock) -> MonoTime(Nil) {
  case process.receive_forever(clock.subject) {
    SetConfig(config) -> {
      loop_internal(InternalClock(..clock, config:))
    }

    SetState(state) -> {
      use time <-
        case clock.state, state {
          PauseSilent, Resume -> queue_tick(clock, _)
          _, _ -> continue_with(clock.time, _)
        }

      loop_internal(
        InternalClock(..clock, time:, state: revise_state(clock.state, state)),
      )
    }

    EmitTick -> {
      case clock.state {
        ResumeTicking -> {
          use time <- queue_tick(clock)
          emit_tick(clock, time)
          loop_internal(InternalClock(..clock, time:))
        }

        PauseTicking -> {
          loop_internal(InternalClock(..clock, state: PauseSilent))
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
