import clock_server.{
  type Config, type ConfigException, BothNonPositive, TicksPerUnitNonPositive,
  UnitsPerSecondNonPositive,
}

import gleam/float
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/time/timestamp.{type Timestamp}
import series.{type Stream, Cons}

const desired_delta_time = 2

const ticks_per_unit = 0.5

const units_per_second = 0.001

pub fn run_tests() -> Result(Nil, String) {
  //use Nil <- result.try(run_clock_server_tests())
  use Nil <- result.try(run_config_validation_tests())
  Ok(Nil)
}

pub fn run_clock_server_tests() -> Result(Nil, String) {
  use config <- result.try(test_new_config(ticks_per_unit, units_per_second))
  let client = clock_server.new_client(todo, todo)
  let timer = series.new(timer_stream(0))
  let _clock = clock_server.new(config, client, fn() { series.next(timer) })
  Ok(Nil)
}

/// Verify that the configuration constructor correctly detects erroneous input.
pub fn run_config_validation_tests() -> Result(Nil, String) {
  use Nil <- result.try(test_config_validation(
    -1.0,
    1.0,
    TicksPerUnitNonPositive,
  ))

  use Nil <- result.try(test_config_validation(
    0.0,
    1.0,
    TicksPerUnitNonPositive,
  ))

  use Nil <- result.try(test_config_validation(
    1.0,
    -1.0,
    UnitsPerSecondNonPositive,
  ))

  use Nil <- result.try(test_config_validation(
    1.0,
    0.0,
    UnitsPerSecondNonPositive,
  ))

  use Nil <- result.try(test_config_validation(-1.0, -1.0, BothNonPositive))

  Ok(Nil)
}

/// The stream [desired_delta_time, 2 * desired_delta_time ...].
fn timer_stream(n: Int) -> Stream(Timestamp) {
  use <- Cons(timestamp.from_unix_seconds(n * desired_delta_time))
  timer_stream(n + 1)
}

/// Check that the configuration constructor succeeds, and return the
/// constructed configuration.
fn test_new_config(tpu: Float, ups: Float) -> Result(Config, String) {
  case clock_server.new_config(tpu, ups) {
    Ok(config) -> Ok(config)
    Error(err) -> fail_test_new_config(err)
  }
}

/// Check that the configuration constructor returns the desired error value on
/// the designated input.
fn test_config_validation(
  tpu: Float,
  ups: Float,
  target_err: ConfigException,
) -> Result(Nil, String) {
  case clock_server.new_config(tpu, ups) {
    Ok(_) -> fail_test_config_validation(tpu, ups, target_err, None)
    Error(result_err) ->
      case target_err == result_err {
        True -> Ok(Nil)
        False ->
          fail_test_config_validation(tpu, ups, target_err, Some(result_err))
      }
  }
}

/// Error value for `test_new_config`.
fn fail_test_new_config(err: ConfigException) -> Result(a, String) {
  Error(
    "Fail: Configuration creation failed unexpectedly with `"
    <> clock_server.config_exception_to_string(err)
    <> "`",
  )
}

/// Error value for `test_config_validation`.
fn fail_test_config_validation(
  tpu: Float,
  ups: Float,
  target_err: ConfigException,
  result_err: Option(ConfigException),
) -> Result(a, String) {
  Error(
    "Fail: Expected error `"
    <> clock_server.config_exception_to_string(target_err)
    <> "` on configuration creation with `ticks_per_unit: "
    <> float.to_string(tpu)
    <> "` and `units_per_second: "
    <> float.to_string(ups)
    <> "`, observed "
    <> case result_err {
      Some(err) -> "`" <> clock_server.config_exception_to_string(err) <> "`"
      None -> "no error"
    },
  )
}
