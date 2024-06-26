/* Copyright (C) 2011-2012 Matthew Fluet.
 * Copyright (C) 1999-2007 Henry Cejtin, Matthew Fluet, Suresh
 *    Jagannathan, and Stephen Weeks.
 * Copyright (C) 1997-2000 NEC Research Institute.
 *
 * MLton is released under a HPND-style license.
 * See the file MLton-LICENSE for details.
 */

GC_thread copyThread (GC_state s, GC_thread from, size_t used) {
  GC_thread to;

  LOG(LM_THREAD, LL_DEBUG,
      "called on "FMTPTR,
      (uintptr_t)from);

  /* newThread may do a GC, which invalidates from.
   * Hence we need to stash from someplace that the GC can find it.
   */
  assert (s->savedThread == BOGUS_OBJPTR);
  s->savedThread = pointerToObjptr((pointer)from - offsetofThread (s), NULL);
  to = newThread (s, alignStackReserved(s, used));
  from = (GC_thread)(objptrToPointer(s->savedThread, NULL) + offsetofThread (s));
  s->savedThread = BOGUS_OBJPTR;
  if (DEBUG_THREADS) {
    fprintf (stderr, FMTPTR" = copyThread ("FMTPTR")\n",
             (uintptr_t)to, (uintptr_t)from);
  }
  copyStack (s,
             (GC_stack)(objptrToPointer(from->stack, NULL)),
             (GC_stack)(objptrToPointer(to->stack, NULL)));
  to->bytesNeeded = from->bytesNeeded;
  to->exnStack = from->exnStack;

  Trace2(EVENT_THREAD_COPY, (EventInt)from, (EventInt)to);

  return to;
}

GC_thread copyThreadWithHeap (GC_state s, GC_thread from, size_t used) {
  GC_thread to;

  LOG(LM_THREAD, LL_DEBUG,
      "called on "FMTPTR,
      (uintptr_t)from);

  /* newThread may do a GC, which invalidates from.
   * Hence we need to stash from someplace that the GC can find it.
   */
  assert (s->savedThread == BOGUS_OBJPTR);
  s->savedThread = pointerToObjptr((pointer)from - offsetofThread (s), NULL);
  to = newThreadWithHeap (s, alignStackReserved(s, used), 0);
  from = (GC_thread)(objptrToPointer(s->savedThread, NULL) + offsetofThread (s));
  s->savedThread = BOGUS_OBJPTR;
  if (DEBUG_THREADS) {
    fprintf (stderr, FMTPTR" = copyThread ("FMTPTR")\n",
             (uintptr_t)to, (uintptr_t)from);
  }
  copyStack (s,
             (GC_stack)(objptrToPointer(from->stack, NULL)),
             (GC_stack)(objptrToPointer(to->stack, NULL)));
  to->bytesNeeded = from->bytesNeeded;
  to->exnStack = from->exnStack;

  to->spareHeartbeatTokens += from->spareHeartbeatTokens;
  from->spareHeartbeatTokens = 0;

#ifdef DETECT_ENTANGLEMENT
  memcpy(
    &(to->decheckSyncDepths[0]),
    &(from->decheckSyncDepths[0]),
    sizeof(uint32_t) * DECHECK_DEPTHS_LEN
  );
#endif

  Trace2(EVENT_THREAD_COPY, (EventInt)from, (EventInt)to);

  return to;
}

void GC_copyCurrentThread (GC_state s) {
  GC_thread fromThread;
  GC_stack fromStack;
  GC_thread toThread;
  LOCAL_USED_FOR_ASSERT GC_stack toStack;

  LOG(LM_THREAD, LL_DEBUG,
      "called");

  enter(s);

  fromThread = (GC_thread)(objptrToPointer(s->currentThread, NULL)
                           + offsetofThread (s));
  fromStack = (GC_stack)(objptrToPointer(fromThread->stack, NULL));
  /* RAM_NOTE: Should this be fromStack->used? */
  toThread = copyThread (s, fromThread, fromStack->used);

  toStack = (GC_stack)(objptrToPointer(toThread->stack, NULL));
  assert (toStack->reserved == alignStackReserved (s, toStack->used));

  leave(s);

  LOG(LM_THREAD, LL_DEBUG,
      "result is "FMTPTR,
      (uintptr_t)toThread);
  assert (s->savedThread == BOGUS_OBJPTR);
  s->savedThread = pointerToObjptr((pointer)toThread - offsetofThread (s), NULL);
}

pointer GC_copyThread (GC_state s, pointer p) {
  GC_thread fromThread;
  GC_stack fromStack;
  GC_thread toThread;
  LOCAL_USED_FOR_ASSERT GC_stack toStack;

  LOG(LM_THREAD, LL_DEBUG,
      "called on "FMTPTR,
      (uintptr_t)p);

  enter(s);

  fromThread = (GC_thread)(p + offsetofThread (s));
  fromStack = (GC_stack)(objptrToPointer(fromThread->stack, NULL));
  assert (fromStack->reserved >= fromStack->used);
  toThread = copyThreadWithHeap (s, fromThread, fromStack->used);
  toStack = (GC_stack)(objptrToPointer(toThread->stack, NULL));
  assert (toStack->reserved == alignStackReserved (s, toStack->used));

  leave(s);

  LOG(LM_THREAD, LL_DEBUG,
      "result is "FMTPTR" from "FMTPTR,
      (uintptr_t)toThread,
      (uintptr_t)fromThread);
  return ((pointer)toThread - offsetofThread (s));
}
