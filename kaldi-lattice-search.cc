#include "base/kaldi-common.h"
#include "util/common-utils.h"
#include "fstext/kaldi-fst-io.h"
#include "lat/kaldi-lattice.h"
#include "lat/lattice-functions.h"

namespace fst {

void ConvertLatticeWeight(const kaldi::CompactLatticeWeight& iw,
                          StdArc::Weight* ow) {
  KALDI_ASSERT(ow != NULL);
  *ow = StdArc::Weight(iw.Weight().Value1() + iw.Weight().Value2());
}

void ConvertLatticeWeight(const kaldi::CompactLatticeWeight& iw,
                          LogArc::Weight* ow) {
  KALDI_ASSERT(ow != NULL);
  *ow = LogArc::Weight(iw.Weight().Value1() + iw.Weight().Value2());
}

}  // namespace fst

namespace kaldi {

void AddInsPenToLattice(BaseFloat penalty, Lattice *lat) {
  typedef typename Lattice::Arc Arc;
  typedef typename Lattice::Weight Weight;
  for (int32 state = 0; state < lat->NumStates(); ++state) {
    for (fst::MutableArcIterator<Lattice> aiter(lat, state);
         !aiter.Done(); aiter.Next()) {
      Arc arc(aiter.Value());
      if (arc.olabel != 0) {
        Weight weight = arc.weight;
        weight.SetValue1(weight.Value1() + penalty);
        arc.weight = weight;
        aiter.SetValue(arc);
      }
    }
  }
}

void AddInsPenToLattice(BaseFloat penalty, CompactLattice *lat) {
  typedef typename CompactLattice::Arc Arc;
  typedef typename CompactLattice::Weight::W Weight;
  for (int32 state = 0; state < lat->NumStates(); ++state) {
    for (fst::MutableArcIterator<CompactLattice> aiter(lat, state);
         !aiter.Done(); aiter.Next()) {
      Arc arc(aiter.Value());
      if (arc.olabel != 0) {
        Weight weight = arc.weight.Weight();
        weight.SetValue1(weight.Value1() + penalty);
        arc.weight.SetWeight(weight);
        aiter.SetValue(arc);
      }
    }
  }
}

template <typename Arc>
double ComputeLikelihood(const fst::Fst<Arc>& fst) {
  typedef fst::Fst<Arc> Fst;
  if (fst.Start() == fst::kNoStateId)
    return -std::numeric_limits<double>::infinity();
  std::vector<typename Arc::Weight> state_likelihoods;
  fst::ShortestDistance(fst, &state_likelihoods);
  typename Arc::Weight total_likelihood = Arc::Weight::Zero();
  for (fst::StateIterator<Fst> siter(fst); !siter.Done(); siter.Next()) {
    const typename Arc::StateId s = siter.Value();
    total_likelihood = fst::Plus(
        total_likelihood, fst::Times(fst.Final(s), state_likelihoods[s]));
  }
  return -total_likelihood.Value();
}

}  // namespace kaldi

int main(int argc, char *argv[]) {
  try {
    using namespace kaldi;

    const char *usage =
        "Search the complex queries over lattices.\n\n"
        "Queries can be an individual FST or, more typically, a table of\n"
        "FSTs.\n"
        "\n"
        "Usage: lattice-search [options] lattice-rspecifier query-rspecifier\n"
        "  e.g.: lattice-search ark:lattices.ark ark:queries.ark\n"
        "  e.g.: lattice-search ark:lattices.ark query.fst\n";

    ParseOptions po(usage);
    BaseFloat acoustic_scale = 1.0;
    BaseFloat graph_scale = 1.0;
    BaseFloat insertion_penalty = 0.0;
    BaseFloat beam = std::numeric_limits<BaseFloat>::infinity();
    bool use_log = true;

    po.Register("use-log", &use_log,
                "If true, compute scores using the log semiring (a.k.a. "
                "forward), otherwise use the tropical semiring (a.k.a. "
                "viterbi).");
    po.Register("acoustic-scale", &acoustic_scale,
                "Scaling factor for acoustic likelihoods in the lattices.");
    po.Register("graph-scale", &graph_scale,
                "Scaling factor for graph probabilities in the lattices.");
    po.Register("insertion-penalty", &insertion_penalty,
                "Add this penalty to the lattice arcs with non-epsilon output "
                "label (typically, equivalent to word insertion penalty).");
    po.Register("beam", &beam, "Pruning beam (applied after acoustic scaling "
                "and adding the insertion penalty).");
    po.Read(argc, argv);

    if (po.NumArgs() != 2) {
      po.PrintUsage();
      exit(1);
    }

    const std::string lattice_in_str = po.GetArg(1);
    const std::string query_in_str = po.GetArg(2);

    const bool lattice_is_table =
        (ClassifyRspecifier(lattice_in_str, NULL, NULL) != kNoRspecifier);
    const bool query_is_table =
        (ClassifyRspecifier(query_in_str, NULL, NULL) != kNoRspecifier);

    std::vector<std::vector<double> > scale(2, std::vector<double>{0.0, 0.0});
    scale[0][0] = graph_scale;
    scale[1][1] = acoustic_scale;

    fst::VectorFst<fst::StdArc> tmp_std;
    fst::VectorFst<fst::LogArc> tmp_log;
    std::vector<fst::VectorFst<fst::StdArc>*> query_std_fsts;
    std::vector<fst::VectorFst<fst::LogArc>*> query_log_fsts;
    std::vector<std::string> query_keys;
    if (query_is_table) {
      SequentialTableReader<fst::VectorFstHolder> query_reader(query_in_str);
      for (; !query_reader.Done(); query_reader.Next()) {
        query_keys.push_back(query_reader.Key());
        if (use_log) {
          query_log_fsts.push_back(new fst::VectorFst<fst::LogArc>());
          fst::ArcMap(query_reader.Value(), query_log_fsts.back(),
                      fst::WeightConvertMapper<fst::StdArc, fst::LogArc>());
        } else {
          query_std_fsts.push_back(new fst::VectorFst<fst::StdArc>());
          *query_std_fsts.back() = query_reader.Value();
        }
        query_reader.FreeCurrent();
      }
    } else {
      if (use_log) {
        fst::ReadFstKaldi(query_in_str, &tmp_std);
        query_log_fsts.push_back(new fst::VectorFst<fst::LogArc>());
        fst::ArcMap(tmp_std, query_log_fsts.back(),
                    fst::WeightConvertMapper<fst::StdArc, fst::LogArc>());
        if (query_log_fsts.back()->Properties(fst::kILabelSorted, false) !=
            fst::kILabelSorted)
          fst::ArcSort(query_log_fsts.back(),
                       fst::ILabelCompare<fst::LogArc>());
      } else {
        query_std_fsts.push_back(new fst::VectorFst<fst::StdArc>());
        fst::ReadFstKaldi(query_in_str, query_std_fsts.back());
        if (query_std_fsts.back()->Properties(fst::kILabelSorted, false) !=
            fst::kILabelSorted)
          fst::ArcSort(query_std_fsts.back(), fst::ILabelCompare<fst::StdArc>());
      }
    }

    std::cout.precision(6);

    if (lattice_is_table) {
      SequentialCompactLatticeReader lattice_reader(lattice_in_str);
      for (; !lattice_reader.Done(); lattice_reader.Next()) {
        const std::string lattice_key = lattice_reader.Key();
        fst::VectorFst<fst::StdArc> lattice_std_fst;
        fst::VectorFst<fst::LogArc> lattice_log_fst;
        {
          CompactLattice lat = lattice_reader.Value();
          lattice_reader.FreeCurrent();
          // Acoustic scale
          if (acoustic_scale != 1.0 || graph_scale != 1.0)
            fst::ScaleLattice(scale, &lat);
          // Word insertion penalty
          if (insertion_penalty != 0.0)
            AddInsPenToLattice(insertion_penalty, &lat);
          // Lattice prunning
          if (beam != std::numeric_limits<BaseFloat>::infinity())
            PruneLattice(beam, &lat);
          // Convert lattice to FST
          fst::ConvertLattice(lat, &lattice_std_fst);
          if (use_log) {
            fst::ArcMap(lattice_std_fst, &lattice_log_fst,
                        fst::WeightConvertMapper<fst::StdArc, fst::LogArc>());
            lattice_std_fst.DeleteStates();
            if (lattice_log_fst.Properties(fst::kOLabelSorted, false) !=
                fst::kOLabelSorted)
              fst::ArcSort(&lattice_log_fst, fst::OLabelCompare<fst::LogArc>());
          } else {
            if (lattice_std_fst.Properties(fst::kOLabelSorted, false) !=
                fst::kOLabelSorted)
              fst::ArcSort(&lattice_std_fst, fst::OLabelCompare<fst::StdArc>());
          }
        }
        // Compute total log-likelihood of the lattice
        const double lattice_likelihood = use_log ?
            ComputeLikelihood(lattice_log_fst) :
            ComputeLikelihood(lattice_std_fst);
        // Compute the log-likelihood of each of the queries
        const size_t num_queries = std::max(query_log_fsts.size(),
                                            query_std_fsts.size());
        for (size_t i = 0; i < num_queries; ++i) {
          double query_likelihood;
          if (use_log) {
            TableCompose(lattice_log_fst, *query_log_fsts[i], &tmp_log);
            query_likelihood = ComputeLikelihood(tmp_log);
          } else {
            TableCompose(lattice_std_fst, *query_std_fsts[i], &tmp_std);
            query_likelihood = ComputeLikelihood(tmp_std);
          }
          if (query_likelihood > lattice_likelihood) {
            const std::string query_msg = i < query_keys.size() ? \
                "query \"" + query_keys[i] + "\"" : "the query";
            KALDI_WARN << "The likelihood for " << query_msg << " is greater "
                       << "than the total likelihood for lattice "
                       << lattice_key << " (" << std::scientific
                       << query_likelihood << " vs. " << std::scientific
                       << lattice_likelihood << ")!";
            query_likelihood = lattice_likelihood;
          }
          if (i < query_keys.size()) {
            std::cout << lattice_key << " " << query_keys[i] << " "
                      << query_likelihood - lattice_likelihood << std::endl;
          } else {
            std::cout << lattice_key << query_likelihood - lattice_likelihood
                      << " " << std::endl;
          }
        }
      }
    } else {
      KALDI_ERR << "NOT IMPLEMENTED!";
    }
    return 0;
  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
}
