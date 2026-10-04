import clock_server_test
import mono_time_test
import series_test

import gleam/io
import gleam/result

pub fn main() -> Nil {
  let assert Ok(Nil) = run_tests()
  Nil
}

/// Test the `series`, `mono_time`, and `clock_server` modules.
pub fn run_tests() -> Result(Nil, String) {
  io.print("`series` tests...")
  use Nil <- result.try(series_test.run_tests())
  io.println(" Passed!")

  io.print("`mono_time` tests...")
  use Nil <- result.try(mono_time_test.run_tests())
  io.println(" Passed!")

  io.print("`clock_server` tests...")
  use Nil <- result.try(clock_server_test.run_tests())
  io.println(" Passed!")

  io.println("All passed")
  Ok(Nil)
}
