import gleam/int
import series.{type Series, type Stream, Cons}

const check_count = 100

/// Verify that a fresh series correctly emits the first `check_count` elements
/// of `int_stream(0)`.
/// 
/// It is argued by parametricity of the generic `Series(a)` type that this
/// stream alone suffices.
pub fn run_tests() -> Result(Nil, String) {
  let stream = int_stream(0)
  let series = series.new(int_stream(0))
  check_prefix_eq(0, check_count, stream, series)
}

/// The stream `[n, n+1, n+2 ...]`.
fn int_stream(n: Int) -> Stream(Int) {
  use <- Cons(n)
  int_stream(n + 1)
}

/// Check that the `n - i`-length prefixes of a stream and a series match.
fn check_prefix_eq(
  i: Int,
  n: Int,
  stream: Stream(Int),
  series: Series(Int),
) -> Result(Nil, String) {
  case i < n {
    True -> {
      let Cons(head, tail) = stream
      let next = series.next(series)

      case head == next {
        True -> check_prefix_eq(i + 1, n, tail(), series)
        False -> fail_prefix_eq(i)
      }
    }

    False -> Ok(Nil)
  }
}

/// Error value for `check_prefix_eq`.
fn fail_prefix_eq(i: Int) -> Result(a, String) {
  Error("Fail: Stream and series disagree at element " <> int.to_string(i))
}
