(* Copyright (C) 2017 Matthew Fluet.
 * Copyright (C) 1999-2006 Henry Cejtin, Matthew Fluet, Suresh
 *    Jagannathan, and Stephen Weeks.
 * Copyright (C) 1997-2000 NEC Research Institute.
 *
 * MLton is released under a BSD-style license.
 * See the file MLton-LICENSE for details.
 *)

functor UnsafeMonoArray (A: MONO_ARRAY_EXTRA): UNSAFE_MONO_ARRAY =
   struct
      open A

      val sub = unsafeSub
      val update = unsafeUpdate
      val create = fromPoly o Array.alloc
   end

functor UnsafeMonoVector (V: MONO_VECTOR_EXTRA): UNSAFE_MONO_VECTOR =
   struct
      open V

      val sub = unsafeSub
   end

functor UnsafePackWord(PW : PACK_WORD_EXTRA) : PACK_WORD =
   struct
      open PW
      val subVec = unsafeSubVec
      val subVecX = unsafeSubVecX
      val subArr = unsafeSubArr
      val subArrX = unsafeSubArrX
      val update = unsafeUpdate
   end

functor UnsafePackReal(PW : PACK_REAL_EXTRA) : PACK_REAL =
   struct
      open PW
      val subVec = unsafeSubVec
      val subArr = unsafeSubArr
      val update = unsafeUpdate
   end

(* This is here so that the code generated by Lex and Yacc will work. *)
structure Unsafe: UNSAFE =
   struct
      structure Array =
         struct
            val sub = Array.unsafeSub
            val update = Array.unsafeUpdate
            val create = Array.array
         end
      structure BoolArray = UnsafeMonoArray (BoolArray)
      structure BoolVector = UnsafeMonoVector (BoolVector)
      structure CharArray = UnsafeMonoArray (CharArray)
      structure CharVector = UnsafeMonoVector (CharVector)
      structure IntArray = UnsafeMonoArray (IntArray)
      structure IntVector = UnsafeMonoVector (IntVector)
      structure Int8Array = UnsafeMonoArray (Int8Array)
      structure Int8Vector = UnsafeMonoVector (Int8Vector)
      structure Int16Array = UnsafeMonoArray (Int16Array)
      structure Int16Vector = UnsafeMonoVector (Int16Vector)
      structure Int32Array = UnsafeMonoArray (Int32Array)
      structure Int32Vector = UnsafeMonoVector (Int32Vector)
      structure Int64Array = UnsafeMonoArray (Int64Array)
      structure Int64Vector = UnsafeMonoVector (Int64Vector)
      structure IntInfArray = UnsafeMonoArray (IntInfArray)
      structure IntInfVector = UnsafeMonoVector (IntInfVector)
      structure LargeIntArray = UnsafeMonoArray (LargeIntArray)
      structure LargeIntVector = UnsafeMonoVector (LargeIntVector)
      structure LargeRealArray = UnsafeMonoArray (LargeRealArray)
      structure LargeRealVector = UnsafeMonoVector (LargeRealVector)
      structure LargeWordArray = UnsafeMonoArray (LargeWordArray)
      structure LargeWordVector = UnsafeMonoVector (LargeWordVector)
      structure RealArray = UnsafeMonoArray (RealArray)
      structure RealVector = UnsafeMonoVector (RealVector)
      structure Real32Array = UnsafeMonoArray (Real32Array)
      structure Real32Vector = UnsafeMonoVector (Real32Vector)
      structure Real64Array = UnsafeMonoArray (Real64Array)
      structure Real64Vector = UnsafeMonoVector (Real64Vector)
      structure Vector =
         struct
            val sub = Vector.unsafeSub
         end
      structure WordArray = UnsafeMonoArray (WordArray)
      structure WordVector = UnsafeMonoVector (WordVector)
      structure Word8Array = UnsafeMonoArray (Word8Array)
      structure Word8Vector = UnsafeMonoVector (Word8Vector)
      structure Word16Array = UnsafeMonoArray (Word16Array)
      structure Word16Vector = UnsafeMonoVector (Word16Vector)
      structure Word32Array = UnsafeMonoArray (Word32Array)
      structure Word32Vector = UnsafeMonoVector (Word32Vector)
      structure Word64Array = UnsafeMonoArray (Word64Array)
      structure Word64Vector = UnsafeMonoVector (Word64Vector)
      structure PackReal32Big = UnsafePackReal(PackReal32Big)
      structure PackReal32Little = UnsafePackReal(PackReal32Little)
      structure PackReal64Big = UnsafePackReal(PackReal64Big)
      structure PackReal64Little = UnsafePackReal(PackReal64Little)
      structure PackRealBig = UnsafePackReal(PackRealBig)
      structure PackRealLittle = UnsafePackReal(PackRealLittle)
      structure PackWord16Big = UnsafePackWord(PackWord16Big)
      structure PackWord16Little = UnsafePackWord(PackWord16Little)
      structure PackWord32Big = UnsafePackWord(PackWord32Big)
      structure PackWord32Little = UnsafePackWord(PackWord32Little)
      structure PackWord64Big = UnsafePackWord(PackWord64Big)
      structure PackWord64Little = UnsafePackWord(PackWord64Little)
   end
