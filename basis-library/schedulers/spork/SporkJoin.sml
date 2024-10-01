structure SporkJoin :>
sig
  include SPORK_JOIN
  val numSpawnsSoFar: unit -> int
  val numEagerSpawnsSoFar: unit -> int
  val numHeartbeatsSoFar: unit -> int
  val numSkippedHeartbeatsSoFar: unit -> int
  val numStealsSoFar: unit -> int
end =
struct
  type word = Word64.word
  fun __inline_always__ w2i w = __inline_always__ Word64.toIntX w
  fun __inline_always__ i2w i = __inline_always__ Word64.fromInt i

  fun __inline_always__ sporkFair y = __inline_always__ Scheduler.SporkJoin.sporkFair y
  fun __inline_always__ sporkGive y = __inline_always__ Scheduler.SporkJoin.sporkGive y
  fun __inline_always__ sporkKeep y = __inline_always__ Scheduler.SporkJoin.sporkKeep y
  fun __inline_always__ sporkFair' y = __inline_always__ Scheduler.SporkJoin.sporkFair' y
  fun __inline_always__ sporkGive' y = __inline_always__ Scheduler.SporkJoin.sporkGive' y
  fun __inline_always__ sporkKeep' y = __inline_always__ Scheduler.SporkJoin.sporkKeep' y

  (* fun __inline_always__ specialize (f: 'a -> 'b): 'a -> 'b = *)
  (*     let fun specializedF a = f a in *)
  (*       fn __inline_always__ a => __inline_never__ specializedF a *)
  (*     end *)

  fun __inline_always__ parXtra (f: 'aa -> 'ar, x: 'aa, g: 'ba -> 'br, y: 'ba): 'ar * 'br =
      Scheduler.SporkJoin.sporkXtraFair {
        body = f,
        body_arg = x,
        spwn = g,
        spwn_arg = y,
        seq  = fn __inline_always__ fr => (fr, __inline_always__ g y),
        sync = fn __inline_always__ fr_gr => fr_gr
      }

  fun __inline_always__ par (f: unit -> 'a, g: unit -> 'b): 'a * 'b =
      parXtra (f, (), g, ())

  val fork = par

  (* ======================================================================= *)
  fun __inline_always__ midpoint (i: word, j: word) =
        i + (Word64.>> (j - i, 0w1))

  fun __inline_always__ wpareduce (i: word, j: word) (z: 'a) (step: word * 'a -> 'a) (merge: 'a * 'a -> 'a): 'a =
      let fun iter (b: 'a) (i: word, j: word): 'a =
              if i >= j then b else
                let val i' = i + 0w1
                    fun __inline_never__ unstolen b' =
                        if i' >= j then b' else
                          let val mid = midpoint (i', j) in
                            sporkFair {
                              body = fn __inline_always__ () => iter b' (i', mid),
                              spwn = fn __inline_always__ () => iter z (mid, j),
                              seq  = fn __inline_always__ b' => iter b' (mid, j),
                              sync = merge
                          }
                          end
                in
                  sporkGive' {
                    body = fn __inline_always__ () => __inline_always__ step (i, b),
                    spwn = fn __inline_always__ () => unstolen z,
                    seq = fn __inline_always__ b' => iter b' (i', j),
                    sync = merge,
                    unstolen = unstolen
                  }
                end
      in
        __inline_always__ iter z (i, j)
      end

  fun __inline_always__ wpareduceSplit (i: word, j: word) (z: 'a) (step: word * 'a -> 'a) (merge: 'a * 'a -> 'a): 'a =
      let fun split (b: 'a) (i: word, j: word): 'a =
              if i >= j then b else
                let val mid = midpoint (i + 0w1, j) in
                  sporkFair {
                    body = fn __inline_always__ () =>
                              let fun loop b i =
                                      if i >= mid then b else
                                        sporkGive' {
                                          body = fn __inline_always__ () => __inline_always__ step (i, b),
                                          spwn = fn __inline_always__ () => split z (i + 0w1, mid),
                                          seq  = fn __inline_always__ b' => loop b' (i + 0w1),
                                          sync = merge,
                                          unstolen = fn __inline_always__ b' => split b' (i + 0w1, mid)
                                        }
                              in
                                __inline_always__ loop b i
                              end,
                    spwn = fn __inline_always__ () => split z (mid, j),
                    seq  = fn __inline_always__ b' => split b' (mid, j),
                    sync = merge
                  }
                end
      in
        __inline_always__ split z (i, j)
      end

  (* No inlining version *)
  fun __inline_never__ wpareduce' (i: word, j: word) (z: 'a) (step: word * 'a -> 'a) (merge: 'a * 'a -> 'a): 'a =
      let fun iter (b: 'a) (i: word, j: word): 'a =
              if i >= j then
                b
              else
                let val i' = i + 0w1
                    fun __inline_never__ unstolen b' =
                        if i' >= j then
                          b'
                        else
                          let val mid = midpoint (i', j) in
                            sporkFair' {
                              body = fn __inline_never__ () => iter b' (i', mid),
                              spwn = fn __inline_never__ () => iter z (mid, j),
                              seq  = fn __inline_never__ b' => iter b' (mid, j),
                              sync = merge,
                              unstolen = fn __inline_never__ b' => iter b' (mid, j)
                            }
                          end
                in
                  sporkGive' {
                    body = fn __inline_never__ () => step (i, b),
                    spwn = fn __inline_never__ () => unstolen z,
                    seq = fn __inline_never__ b' => iter b' (i', j),
                    sync = merge,
                    unstolen = unstolen
                  }
                end
      in
        iter z (i, j)
      end

  local
    fun __inline_always__ wrap (reduce: word * word -> 'a -> (word * 'a -> 'a) -> ('a * 'a -> 'a) -> 'a)
             (i: int, j: int) (b: 'a) (step: int * 'a -> 'a) (merge: 'a * 'a -> 'a): 'a =
        __inline_always__ reduce (i2w i, i2w j) b (fn __inline_always__ (w, a) => __inline_always__ step (w2i w, a)) merge
  in
  fun __inline_always__ pareduce (i: int, j: int) (b: 'a) (step: int * 'a -> 'a) (merge: 'a * 'a -> 'a): 'a =
      wrap wpareduce (i, j) b step merge
  fun __inline_never__ pareduce' (i: int, j: int) (b: 'a) (step: int * 'a -> 'a) (merge: 'a * 'a -> 'a): 'a =
      wrap wpareduce' (i, j) b step merge
  fun __inline_always__ pareduceSplit (i: int, j: int) (b: 'a) (step: int * 'a -> 'a) (merge: 'a * 'a -> 'a): 'a =
      wrap wpareduceSplit (i, j) b step merge
  end

  fun __inline_always__ parfor (grain: int) (i: int, j: int) (f: int -> unit): unit =
      pareduce (i, j) () (fn __inline_always__ (i, ()) => __inline_always__ f i) (fn ((), ()) => ())

  fun alloc n =
    let
      fun for (i, j) f = if i >= j then () else (f i; for (i+1, j) f)
      val a = ArrayExtra.Raw.alloc n
      val grain = 10000
      val _ =
        if ArrayExtra.Raw.uninitIsNop a then ()
        else parfor 10000 (0, n) (fn i => ArrayExtra.Raw.unsafeUninit (a, i))
    in
      ArrayExtra.Raw.unsafeToArray a
    end

  val maxForkDepthSoFar = Scheduler.maxForkDepthSoFar
  val numSpawnsSoFar = Scheduler.numSpawnsSoFar
  val numEagerSpawnsSoFar = Scheduler.numEagerSpawnsSoFar
  val numHeartbeatsSoFar = Scheduler.numHeartbeatsSoFar
  val numSkippedHeartbeatsSoFar = Scheduler.numSkippedHeartbeatsSoFar
  val numStealsSoFar = Scheduler.numStealsSoFar

  val idleTimeSoFar = Scheduler.IdleTimer.cumulative
  val workTimeSoFar = Scheduler.WorkTimer.cumulative

  fun communicate () = ()
end
