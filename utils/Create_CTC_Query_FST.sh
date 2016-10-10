#!/bin/bash
#
# MIT License
#
# Copyright (c) 2016 Joan Puigcerver <joapuipe@gmail.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
set -e;
export LC_NUMERIC=C;

start_delimiters="";
end_delimiters="";
verbose=1000;
usage="
Usage: ${0##*/} [options] <symbols-table> <not-a-symbol> <strings-table> <fst-wspecifier>

Description:
  Formally, for each input string (s1 s2 ... sN) this util creates a DFA (in
  the form of a FST) representing the language(*):

  (\Sigma^* [\B* <delimiters>+])? \B* s1+ \B* s2+ ... \B* sN+ ([\B* <delimiters>+] \Sigma^*)?

  The alphabet of the language (\Sigma) is obtained from the symbols table
  <symbols-table> (each line maps a symbol from the alphabet to an integer
  value, i.e. Kaldi symbols tables).

  The <not-a-symbol> (\B) can be emitted in between of any two regular symbols,
  except in the case of two equal symbols from the input string, in which case
  the emission of <not-a-symbol> is mandatory (see the CTC definition).

  The input strings are read from the <strings-table> file (or stdin). Each
  line represents a string, identified by the first token, formed by the
  sequence of symbols in the rest of the line.

  The result is written as a table of FSTs using the given <fst-wspecifier>.

Options:
  --start-delimiters  : (string, default = \"$delimiters\")
                        Set of starting delimiter symbols, separated by whitespaces.
  --end-delimiters    : (string, default = \"$delimiters\")
                        Set of ending delimiter symbols, separated by whitespaces.
  --delimiters        : (string, default = \"$delimiters\")
                        Set both starting and ending delimiter symbols, separated by whitespaces.
  --verbose     : (integer, default = $verbose)
                  Print query processing info every 'verbose' queries.
";
while [ "${1:0:2}" = "--" ]; do
    case "$1" in
  "--start-delimiters")
      start_delimiters="$2";
      shift 2;
      ;;
  "--end-delimiters")
      end_delimiters="$2";
      shift 2;
      ;;
  "--delimiters")
      start_delimiters="$2";
      end_delimiters="$2";
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

gawk -v STF="$1" -v SDLM="$start_delimiters" -v EDLM="$end_delimiters" -v BLANK="$2" -v verbose="$verbose" '
BEGIN{
  max_id=0; numq=0;
  while ((getline < STF) > 0) {
    if ($2 > max_id) max_id=$2;       # store the largest symbol ID
    if ($2 != 0) { SYMBS[$1] = $2; }  # store non-epsilon symbols into SYMBS
  }
  NDS = split(SDLM, SDELIMITERS);
  for (s in SDELIMITERS) {
    if (!(SDELIMITERS[s] in SYMBS)) {
      print "SYMBOL \"" SDELIMITERS[s] "\" NOT FOUND IN THE SYMBOLS TABLE!" > "/dev/stderr"; exit 1;
    }
  }
  NDE = split(EDLM, EDELIMITERS);
  for (s in EDELIMITERS) {
    if (!(EDELIMITERS[s] in SYMBS)) {
      print "SYMBOL \"" EDELIMITERS[s] "\" NOT FOUND IN THE SYMBOLS TABLE!" > "/dev/stderr"; exit 1;
    }
  }
  if (!(BLANK in SYMBS)) {
    print "SYMBOL \"" BLANK "\" NOT FOUND IN THE SYMBOLS TABLE!" > "/dev/stderr"; exit 1;
  }
  BLANK = SYMBS[BLANK];
  cmd="(fstcompile --acceptor | fstdeterminizestar --use-log=false | fstminimizeencoded | fstarcsort --sort_type=ilabel | fstprint) 2> /dev/null";
  ## Uncomment this to debug the automaton
  cmd="(fstcompile --acceptor --keep_state_numbering | fstprint) 2> /dev/null";
}NF > 0{
  ++numq;
  if (numq % verbose == 0) {
    printf("Processing query number %d ...\n", numq) > "/dev/stderr";
  }
  print $1;
  if (NF > 1) {
    N = NF - 1;
    missing_symbols = 0;
    for (i=2; i <= NF && !missing_symbols; ++i) {
      if (!($i in SYMBS)) {
        print "SYMBOL \"" $i "\" NOT FOUND IN THE SYMBOLS TABLE!" > "/dev/stderr";
        missing_symbols = 1;
      }
    }
    if (!missing_symbols) {
      W_BEG = 3 * NDS + 2;                      # State where the keyword begins
      W_END = 3 * NDS + N * 2 + 2;              # State where the keyword ends
      FINAL = 3 * ( NDS + NDE ) + N * 2 + 4;    # Final state
      # Line can start with: (\Sigma^* [<start_delimiters>])?
      print 0, 1, 0 | cmd;
      print 0, W_BEG, 0 | cmd;
      for (s in SYMBS) { print 1, 1, SYMBS[s] | cmd; }
      if (NDS > 0) {
        for (i in SDELIMITERS) {
          s = SYMBS[SDELIMITERS[i]];
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
      for (i = 2; i <= NF; ++i) {
        s = SYMBS[$i];
        s_b = W_BEG + (i - 2) * 2;
        print s_b, s_b + 1, BLANK                     | cmd;
        if (i > 0 && ps != s) { print s_b, s_b + 2, s | cmd; }
        print s_b + 1, s_b + 1, BLANK                 | cmd;
        print s_b + 1, s_b + 2, s                     | cmd;
        print s_b + 2, s_b + 2, s                     | cmd;
        ps = s;
      }
      if (NDE > 0) {
        for (i in EDELIMITERS) {
          s = SYMBS[EDELIMITERS[i]];
          s_b = W_END + 1 + (i - 1) * 3;
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
    }
  } else {
    ## The string is not empty, accept \Sigma^*
    for (s in SYMBS) { print 0, 0, SYMBS[s] | cmd; }
    print 0;
  }
  close(cmd);
  print "";
}' "$3" | fstcopy ark:- "$4";
