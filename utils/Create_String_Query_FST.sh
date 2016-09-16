#!/bin/bash
set -e;
export LC_NUMERIC=C;

delimiters="";
verbose=1000;
usage="
Usage: ${0##*/} [options] <symbols-table> <strings-table> <fst-wspecifier>

Description:
  Formally, for each input string (s1 s2 ... sN) this util creates a DFA (in
  the form of a FST) representing the language:

  (\Sigma^* [<delimiters>])? s1 s2 ... sN  ([<delimiters>] \Sigma^*)?

  The alphabet of the language (\Sigma) is obtained from the symbols table
  <symbols-table> (each line maps a symbol from the alphabet to an integer
  value, i.e. Kaldi symbols tables).

  The input strings are read from the <strings-table> file (or stdin). Each
  line represents a string, identified by the first token, formed by the
  sequence of symbols in the rest of the line.

  The result is written as a table of FSTs using the given <fst-wspecifier>.

Options:
  --delimiters  : (string, default = \"$delimiters\")
                  Set of delimiter symbols, separated by whitespaces.
  --verbose     : (integer, default = $verbose)
                  Print query processing info every 'verbose' queries.
";
while [ "${1:0:2}" = "--" ]; do
    case "$1" in
	--delimiters)
	    delimiters="$2";
	    shift 2;
	    ;;
	"--verbose")
	    verbose="$2";
	    shift 2;
	    ;;
	"--help")
	    echo "$usage" >&2 && exit 0;
	    ;;
	*)
	    echo "Unknown option: \"$1\" for ${0##*/}" >&2 && exit 1;
    esac;
done;
[ $# -ne 3 ] && echo "$usage" >&2 && exit 1;

function check_exec() {
    any_missing=0;
    while [ $# -gt 0 ]; do
	which "$1" &> /dev/null || (
	    echo "Executable \"$1\" was not found in your PATH!" >&2;
	    any_missing=1;
	);
	shift 1;
    done
    return $any_missing;
}
check_exec gawk fstcompile fstcopy fstdeterminizestar fstminimizeencoded \
    fstarcsort fstprint || exit 1;

gawk -v STF="$1" -v DLM="$delimiters " -v verbose="$verbose" '
BEGIN{
  max_id=0; numq=0;
  while ((getline < STF) > 0) {
    if ($2 > max_id) max_id=$2;       # store the largest symbol ID
    if ($2 != 0) { SYMBS[$1] = $2; }  # store non-epsilon symbols into SYMBS
  }
  ND = split(DLM, DELIMITERS, " ");
  for (s in DELIMITERS) {
    if (!(DELIMITERS[s] in SYMBS)) {
      print "SYMBOL \"" DELIMITERS[s] "\" NOT FOUND IN THE SYMBOLS TABLE!" > "/dev/stderr"; exit 1;
    }
  }
  cmd="(fstcompile --acceptor | fstdeterminizestar --use-log=false | fstminimizeencoded | fstarcsort --sort_type=ilabel | fstprint) 2> /dev/null";
  ## Uncomment this to debug the automaton
  ##cmd="(fstcompile --acceptor --keep_state_numbering | fstprint) 2> /dev/null";
}NF > 0{
  ++numq;
  if (numq % verbose == 0) {
    printf("Processing query number %d ...\n", numq) > "/dev/stderr";
  }
  print $1;
  if (NF > 1) {
    ## The string is not empty
    N = NF - 1;
    missing_symbols = 0;
    for (i=2; i <= NF && !missing_symbols; ++i) {
      if (!($i in SYMBS)) {
        print "SYMBOL \"" $i "\" NOT FOUND IN THE SYMBOLS TABLE!" > "/dev/stderr";
        missing_symbols = 1;
      }
    }
    if (!missing_symbols) {
      print 0, 1, 0 | cmd;
      print 0, 2, 0 | cmd;
      for (s in SYMBS) { print 1, 1, SYMBS[s] | cmd; }
      if (ND > 0) {
        for (s in DELIMITERS) { print 1, 2, SYMBS[DELIMITERS[s]] | cmd; }
      } else {
        print 1, 2, 0 | cmd;
      }
      for (i=2; i <= NF; ++i) {
        s=SYMBS[$i];
        print i, i + 1, s | cmd;
      }
      if (ND > 0) {
        for (s in DELIMITERS) { print N + 2, N + 3, SYMBS[DELIMITERS[s]] | cmd; }
      } else {
        print N + 2, N + 3, 0 | cmd;
      }
      print N + 2, N + 4, 0 | cmd;
      for (s in SYMBS) { print N + 3, N + 3, SYMBS[s] | cmd; }
      print N + 3, N + 4, 0 | cmd;
      print N + 4 | cmd;
    }
  } else {
    ## The string is not empty, accept \Sigma^*
    for (s in SYMBS) { print 0, 0, SYMBS[s] | cmd; }
    print 0;
  }
  close(cmd);
  print "";
}' "$2" | fstcopy ark:- "$3";
