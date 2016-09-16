#!/bin/bash
set -e;
export LC_NUMERIC=C;

verbose=1000;
usage="
Usage: ${0##*/} [options] <symbols-table> <keywords-list> <fst-wspecifier>

Description:

  Formally, for each keyword in <keywords-list> creates a DFA (in the form
  of a FST) representing the language:

  \Sigma^* keyword \Sigma^*

  The alphabet of the language (\Sigma) is obtained from the symbols
  table <symbols-table> (each row, maps a symbol to an integer value).

Options:
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

gawk -v STF="$1" -v verbose="$verbose" '
BEGIN{
  max_id=0; numq=0;
  while ((getline < STF) > 0) {
    if ($2 > max_id) max_id=$2;       # store the largest symbol ID
    if ($2 != 0) { SYMBS[$1] = $2; }  # store non-epsilon symbols into SYMBS
  }
  cmd="(fstcompile --acceptor | fstdeterminizestar --use-log=false | fstminimizeencoded | fstarcsort --sort_type=ilabel | fstprint) 2> /dev/null";
}{
  ++numq;
  if (numq % verbose == 0) {
    printf("Processing query number %d ...\n", numq) > "/dev/stderr";
  }
  N = length($1);
  print $1;
  # keyword can be preceded by any symbol
  for (s in SYMBS) { print 0, 0, SYMBS[s] | cmd; }
  # if the keyword is found in the line, transition to a final state.
  if ($1 in SYMBS) {
    print 0, 1, SYMBS[$1] | cmd;
  } else {
    print "SYMBOL \"" $1 "\" NOT FOUND IN THE SYMBOLS TABLE!" > "/dev/stderr";
    print 0, 1, max_id + 1 | cmd;
  }
  # once the keyword is found, it can be followed by any symbol
  for (s in SYMBS) { print 1, 1, SYMBS[s] | cmd; }
  print 1 | cmd;
  close(cmd);
  print "";
}' "$2" | fstcopy ark:- "$3";
