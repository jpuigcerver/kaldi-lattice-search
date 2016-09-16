#!/bin/bash
set -e;
export LC_NUMERIC=C;

delimiters="<s> </s> <space>";
verbose=1000;
usage="
Usage: ${0##*/} [options] <symbols-table> <keywords-list> <fst-wspecifier>

Description:

  Formally, for each keyword in <keywords-list> creates a DFA (in the form
  of a FST) representing the language:

  (\Sigma^* [<delimiters>]+)? k e y w o r d ([<delimiters>]+ \Sigma^*)?

  The alphabet of the language (\Sigma) is obtained from the symbols
  table <symbols-table> (each row, maps a symbol to an integer value).

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
}{
  ++numq;
  if (numq % verbose == 0) {
    printf("Processing query number %d ...\n", numq) > "/dev/stderr";
  }
  N = length($1);
  print $1;
  print 0, 1, 0 | cmd;
  print 0, 2, 0 | cmd;
  for (s in SYMBS) { print 1, 1, SYMBS[s] | cmd; }
  if (ND > 0) {
    for (s in DELIMITERS) { print 1, 2, SYMBS[DELIMITERS[s]] | cmd; }
  } else {
    print 1, 2, 0 | cmd;
  }
  for (i=1; i <= N; ++i) {
    s=substr($1, i, 1);
    if (s in SYMBS) {
      print i + 1, i + 2, SYMBS[s] | cmd;
    } else {
      print "SYMBOL \"" s "\" NOT FOUND IN THE SYMBOLS TABLE!" > "/dev/stderr";
      print i + 1, i + 2, max_id + 1 | cmd;
    }
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
  close(cmd);
  print "";
}' "$2" | fstcopy ark:- "$3";
