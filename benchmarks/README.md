To benchmark ICover against all the instances, execute benchmarks.sh as follows:

```
  ./benchmarks.sh
```

The results will be outputted to the terminal and also be stored in the `./results/` folders of each suite. It is also possible to benchmark [Petrinizer](https://github.com/cryptica/pnerf), [mist](http://www.cprover.org/bfc/) and [Bfc](http://www.cprover.org/bfc/) respectively with the argument `petrinizer`, `mist` and `bfc`, e.g.:

```
./benchmarks/benchmarks.sh bfc
```

In order to benchmark Petrinizer and Bfc, read `README.md` from their respective folders. In order to benchmark mist, install it from https://github.com/pierreganty/mist/.

The original [QCover](https://github.com/blondimi/qcover) implementation can be benchmarked with the argument `qcover'.
