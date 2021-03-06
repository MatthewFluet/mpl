/* Copyright (C) 1999-2017 Henry Cejtin, Matthew Fluet, Suresh
 *    Jagannathan, and Stephen Weeks.
 * Copyright (C) 1997-2000 NEC Research Institute.
 *
 * MLton is released under a HPND-style license.
 * See the file MLton-LICENSE for details.
 */

#include <stdatomic.h>

/* AG_NOTE the following SC atomics should be converted to R/A */

#define INVALID_PROC ((char)255)

void lock_init(lock_t *lock) {
  assert (lock);

  atomic_store(lock, (char)INVALID_PROC);
}

void lock_lock_explicit(lock_t *lock, bool check) {
  assert (lock);

  GC_state s = pthread_getspecific(gcstate_key);
  char expected = INVALID_PROC;
  size_t cpoll = 0;
  double prob = 1.0;

  while (true) {
    bool tryCAS = false;
    if (1.0 <= prob) {
      tryCAS = true;
    } else {
      double flip;
      drand48_r(&(s->tlsObjects.drand48_data), &flip);
      if (flip <= prob) {
        tryCAS = true;
      }
    }

    if (tryCAS &&
        (atomic_compare_exchange_strong(lock,
                                        &expected,
                                        (char)Proc_processorNumber(s)))) {
      break;
    }

    if (INVALID_PROC == atomic_load(lock)) {
      /* I may have won if I tried, so increase prob */
      prob *= 2.0;
      if (prob > 1.0) {
        prob = 1.0;
      }
    } else {
      /* I lost, or would have lost, so decrease prob */
      double newProb = prob / 2.0;
      if (0.0 < newProb) {
        /* make sure prob doesn't bottom out at zero */
        prob = newProb;
      }
    }

    if (check && expected == (char)Proc_processorNumber(s)) {
      DIE ("Trying to acquire lock %p that I already own",
           (_Atomic void *)lock);
    }
    expected = INVALID_PROC;

    if (GC_CheckForTerminationRequestRarely(s, &cpoll)) {
        GC_TerminateThread(s);
    }
  }
}

void lock_unlock_explicit(lock_t *lock, bool check) {
  assert(lock);

  GC_state s = pthread_getspecific(gcstate_key);
  char expected = (char)Proc_processorNumber(s);


  if (check) {
    if (!atomic_compare_exchange_strong(lock,
                                        &expected,
                                        INVALID_PROC)) {
      DIE("Trying to unlock %p which is instead locked by %u",
          (_Atomic char *)lock,
          expected);
    }
  } else {
    atomic_store(lock, INVALID_PROC);
  }
}

void lock_lock(lock_t *lock) {
  lock_lock_explicit(lock, true);
}

void lock_unlock(lock_t *lock) {
  lock_unlock_explicit(lock, true);
}

bool lock_is_locked(const lock_t *lock) {
  assert (lock);

  return atomic_load(lock) != INVALID_PROC;
}

bool lock_is_locked_by_me(const lock_t *lock) {
  assert (lock);

  GC_state s = pthread_getspecific(gcstate_key);
  return atomic_load(lock) == (char)Proc_processorNumber(s);
}

void rwlock_init(rwlock_t *lock) {
    lock_init(&lock->reader_lock);
    lock_init(&lock->writer_lock);
    lock->readers_in_section = 0;
}

void rwlock_reader_lock(GC_state s, rwlock_t *lock) {
    assert (lock);
    uint32_t readers;

    lock_lock(&lock->reader_lock);

    readers = atomic_load_explicit(&lock->readers_in_section,
                                   memory_order_acquire) + 1;
    atomic_store_explicit(&lock->readers_in_section,
                          readers,
                          memory_order_release);
    if (readers == 1) {
        lock_lock_explicit(&lock->writer_lock, true);
    }
    assert (lock_is_locked(&lock->writer_lock));

    lock_unlock(&lock->reader_lock);
    Trace2(EVENT_RWLOCK_R_TAKE, (EventInt)lock, readers);
}

void rwlock_reader_unlock(GC_state s, rwlock_t *lock) {
    assert (lock);
    uint32_t readers;
    lock_lock(&lock->reader_lock);

    readers = atomic_load_explicit(&lock->readers_in_section,
                                   memory_order_acquire) - 1;
    atomic_store_explicit(&lock->readers_in_section,
                          readers,
                          memory_order_release);
    if (readers == 0) {
        lock_unlock_explicit(&lock->writer_lock, false);
    }

    lock_unlock(&lock->reader_lock);
    Trace2(EVENT_RWLOCK_R_RELEASE, (EventInt)lock, readers);
}

void rwlock_writer_lock(GC_state s, rwlock_t *lock) {
    assert (lock);
    lock_lock_explicit(&lock->writer_lock, false);
    Trace1(EVENT_RWLOCK_W_TAKE, (EventInt)lock);
}

void rwlock_writer_unlock(GC_state s, rwlock_t *lock) {
    assert (lock);
    lock_unlock(&lock->writer_lock);
    Trace1(EVENT_RWLOCK_W_RELEASE, (EventInt)lock);
}

lock_status rwlock_status(const rwlock_t *lock) {
  assert (lock);

  lock_status res;
  uint16_t readers;

  readers = atomic_load_explicit(&lock->readers_in_section,
                                 memory_order_relaxed);

  if (readers > 0) {
    res = RWLOCK_STATUS_READERS;
  } else if (lock_is_locked(&lock->writer_lock)) {
    res = RWLOCK_STATUS_WRITER;
  } else {
    res = RWLOCK_STATUS_NOBODY;
  }

  return res;
}

bool rwlock_is_locked_by_me_for_writing(const rwlock_t *lock) {
  assert (lock);

  return lock_is_locked_by_me(&lock->writer_lock);
}
