#!/bin/bash
set -e;
export LC_NUMERIC=C;

delimiters="<s> </s> <space>";
verbose=1000;
usage="
Usage: ${0##*/} [options] <symbols-table> <no-symbol> <keywords-list> <fst-wspecifier>

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
[ $# -ne 4 ] && echo "$usage" >&2 && exit 1;

gawk -v STF="$1" -v DLM="$delimiters " -v BLANK="$2" -v verbose="$verbose" '
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
  if (!(BLANK in SYMBS)) {
    print "SYMBOL \"" BLANK "\" NOT FOUND IN THE SYMBOLS TABLE!" > "/dev/stderr"; exit 1;
  }
  BLANK = SYMBS[BLANK];
  cmd="(fstcompile --acceptor | fstdeterminizestar --use-log=false | fstminimizeencoded | fstarcsort --sort_type=ilabel | fstprint) 2> /dev/null";
}NF > 0{
  ++numq;
  if (numq % verbose == 0) {
    printf("Processing query number %d ...\n", numq) > "/dev/stderr";
  }
  print $1;

  N = length($1);
  missing_symbols = 0;
  for (i=1; i <= N && !missing_symbols; ++i) {
    s=substr($1, i, 1);
    if (!(s in SYMBS)) {
      print "SYMBOL \"" s "\" NOT FOUND IN THE SYMBOLS TABLE!" > "/dev/stderr";
      missing_symbols = 1;
    }
  }

  if (!missing_symbols) {
    W_BEG = 3 * ND + 2;            # State where the keyword begins
    W_END = 3 * ND + N * 2 + 2;    # State where the keyword ends
    FINAL = 6 * ND + N * 2 + 4;    # Final state
    # Line can start with: (\Sigma^* [<delimiters>])?
    print 0, 1, 0 | cmd;
    print 0, W_BEG, 0 | cmd;
    for (s in SYMBS) { print 1, 1, SYMBS[s] | cmd; }
    if (ND > 0) {
      for (i in DELIMITERS) {
        s = SYMBS[DELIMITERS[i]];
        s_b = 2 + (i - 1) * 3;
        print 1, s_b, 0               | cmd;
        print s_b, s_b + 1, BLANK     | cmd;
        print s_b, s_b + 2, s         | cmd;
        print s_b + 1, s_b + 1, BLANK | cmd;
        print s_b + 1, s_b + 2, s     | cmd;
        print s_b + 2, s_b + 2, s     | cmd;
        print s_b + 2, W_BEG, 0       | cmd;
      }
    } else {
      print 1, W_BEG, 0 | cmd;
    }
    # Line must contain the keyword: k e y w o r d
    ps = "";
    for (i = 1; i <= N; ++i) {
      s = SYMBS[substr($1, i, 1)];
      s_b = W_BEG + (i - 1) * 2;
      print s_b, s_b + 1, BLANK                     | cmd;
      if (i > 0 && ps != s) { print s_b, s_b + 2, s | cmd; }
      print s_b + 1, s_b + 1, BLANK                 | cmd;
      print s_b + 1, s_b + 2, s                     | cmd;
      print s_b + 2, s_b + 2, s                     | cmd;
      ps = s;
    }
    if (ND > 0) {
      for (i in DELIMITERS) {
        s = SYMBS[DELIMITERS[i]];
        s_b = W_END + 1 + (i - 1)* 3;
        print W_END, s_b, 0           | cmd;
        print s_b, s_b + 1, BLANK     | cmd;
        print s_b, s_b + 2, s         | cmd;
        print s_b + 1, s_b + 1, BLANK | cmd;
        print s_b + 1, s_b + 2, s     | cmd;
        print s_b + 2, s_b + 2, s     | cmd;
        print s_b + 2, FINAL - 1, 0   | cmd;
      }
    } else {
      print W_END, FINAL - 1, 0 | cmd;
    }
    print W_END, FINAL, 0 | cmd;
    for (s in SYMBS) { print FINAL - 1, FINAL - 1, SYMBS[s] | cmd; }
    print FINAL - 1, FINAL, 0 | cmd;
    print FINAL | cmd;
    close(cmd);
  }
  print "";
}' "$3" | fstcopy ark:- "$4";
