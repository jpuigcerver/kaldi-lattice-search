# kaldi-lattice-search
Search stuff in Kaldi lattices (stuff = any language represented by a DFA)

## Compile & install

You need to define the environment variable KALDI_ROOT to point to your Kaldi distribution.

```bash
export KALDI_ROOT=/path/to/your/kaldi/distribution
make depend
make
```

Once compiled, you can install the binary to PREFIX/bin (by default PREFIX=/usr/local):
```bash
make install
```

## Lattices

Any Kaldi lattices are valid.

## Queries

Formally, for each lattice and query, you are computing the probability that the query is
contained somewhere in the lattice. Any DFA (Deterministic Finite Automaton) can be used
as a query, but remember: THEY MUST BE DETERMINISTIC, otherwise you'll find strange results.

You have some examples to produce these kind of DFAs in the utils folder.

- **utils/Create_String_Query_FST.sh**: Given a table of query strings, for each query create a
  DFA that accepts any string containing the query.
- **utils/Create_CTC_Query_FST.sh**: Very similar to the previous tool, but uses the CTC representation
  of each query string.
