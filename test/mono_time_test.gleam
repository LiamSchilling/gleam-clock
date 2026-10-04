import mono_time.{
  type MonoTime, type MonoTimeException, ObservedDecreasingTimestamp,
}

import gleam/int
import gleam/time/timestamp.{type Timestamp}
import series.{type Stream, Cons}

const check_count = 100

const where_fail = 50

/// Verify that a fresh monadic context correctly checks the first `check_count`
/// timestamps from `raw_stream(0)`, detecting the erroneous timestamp at the
/// `where_fail` element.
pub fn run_tests() -> Result(Nil, String) {
  let stream = validated_stream(0)
  let series = series.new(raw_stream(0))
  mono_time.run(check_prefix_eq(0, check_count, stream), fn() {
    series.next(series)
  })
}

/// If `where_fail` is `2 * (n+1)`, then the stream
/// `[0, 0, 1, 1 ... n, n, n-1, n-1, n+2, n+2 ...]`.
fn raw_stream(n: Int) -> Stream(Timestamp) {
  use <- Cons(case n < where_fail {
    True -> timestamp.from_unix_seconds(n / 2)
    False -> timestamp.from_unix_seconds(n / 2 - 2)
  })

  raw_stream(n + 1)
}

/// If `where_fail` is `2 * (n+1)`, then the stream
/// `[0, 0, 1, 1 ... n, n, Error(0), ERROR(1), Error(2), ...]`.
fn validated_stream(n: Int) -> Stream(Result(Timestamp, MonoTimeException)) {
  use <- Cons(case n < where_fail {
    True -> Ok(timestamp.from_unix_seconds(n / 2))
    False -> Error(ObservedDecreasingTimestamp(n - where_fail))
  })

  validated_stream(n + 1)
}

/// Check that the `n - i`-length prefix of a stream matches the prefix of
/// timestamps provided by the monadic context.
fn check_prefix_eq(
  i: Int,
  n: Int,
  stream: Stream(Result(Timestamp, MonoTimeException)),
) -> MonoTime(Result(Nil, String)) {
  case i < n {
    True -> {
      let Cons(head, tail) = stream
      use next <- mono_time.bind(mono_time.get())

      case head == next {
        True -> check_prefix_eq(i + 1, n, tail())
        False -> mono_time.pure(fail_prefix_eq(i))
      }
    }

    False -> mono_time.pure(Ok(Nil))
  }
}

/// Error value for `check_prefix_eq`.
fn fail_prefix_eq(i: Int) -> Result(a, String) {
  Error("Fail: Incorrect timestamp at query " <> int.to_string(i))
}
