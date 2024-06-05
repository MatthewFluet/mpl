structure ForkJoin = MkForkJoin (val fork = fn (f, g) =>
                                    Scheduler.SporkJoin.spork
                                    (f, g, fn a => (a, g ()), fn (a, b) => (a, b)))
