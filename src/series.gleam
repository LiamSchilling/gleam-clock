//// A server that emits a series of elements.
//// 
//// For use in the package's testing suite.

import gleam/erlang/process.{type Subject}

/// A lazily evaluated stream, so that only the head element is ever fully
/// evaluated.
pub type Stream(a) {
  Cons(head: a, tail: fn() -> Stream(a))
}

/// A series server identifier, along which each next element may be queried.
pub opaque type Series(a) {
  Series(query: Subject(Nil), return: Subject(a))
}

/// Construct a series from a pure stream value.
pub fn new(stream: Stream(a)) -> Series(a) {
  let reply = process.new_subject()
  let return = process.new_subject()

  process.spawn(fn() {
    let series = Series(query: process.new_subject(), return:)
    process.send(reply, series)
    loop(series, stream)
  })

  process.receive_forever(reply)
}

/// Retrieve the next element from a series, and advance the series.
pub fn next(series: Series(a)) -> a {
  process.send(series.query, Nil)
  process.receive_forever(series.return)
}

fn loop(client: Series(a), stream: Stream(a)) -> Nil {
  process.receive_forever(client.query)
  let Cons(head, tail) = stream
  process.send(client.return, head)
  loop(client, tail())
}
