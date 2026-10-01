//// Provides an isomorphism between pure streams (implemented as lazy lists)
//// and effectful sequences (implemented as a server).
//// 
//// Used only by the package's testing suite.

import gleam/erlang/process.{type Subject}

/// A lazily evaluated stream, so that only the head element is ever fully
/// evaluated.
pub type Stream(a) {
  Cons(head: a, tail: fn() -> Stream(a))
}

/// A sequence server identifier, along which each next element may be queried.
pub opaque type Sequence(a) {
  Sequence(query: Subject(Nil), return: Subject(a))
}

/// The elimination form for sequences. Retrieve the next element.
pub fn next(sequence: Sequence(a)) -> a {
  process.send(sequence.query, Nil)
  process.receive_forever(sequence.return)
}

/// Convert a stream into a sequence.
pub fn into(stream: Stream(a)) -> Sequence(a) {
  let reply = process.new_subject()
  let return = process.new_subject()

  process.spawn(fn() {
    let sequence = Sequence(query: process.new_subject(), return:)
    process.send(reply, sequence)
    loop(sequence, stream)
  })

  process.receive_forever(reply)
}

/// Convert a sequence into a stream.
pub fn from(sequence: Sequence(a)) -> Stream(a) {
  use <- Cons(next(sequence))
  from(sequence)
}

fn loop(client: Sequence(a), stream: Stream(a)) -> Nil {
  process.receive_forever(client.query)
  let Cons(head, tail) = stream
  process.send(client.return, head)
  loop(client, tail())
}
