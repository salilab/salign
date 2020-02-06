# profile-profile alignment using salign
from __future__ import print_function
from modeller import *

def run():
    log.level(1, 0, 1, 1, 1)
    env = environ()

    aln = alignment(env, file='HB_ALIFILE_HB', alignment_format='PIR')

    aln.salign(rr_file='${LIB}/blosum62.sim.mat',
               gap_penalties_1d=(HB_GAP_PEN_1D_HB), output='',
               align_block=HB_BLOCK1SEQS_HB,   # no. of seqs. in first MSA
               align_what='PROFILE', alignment_type='PAIRWISE',
               comparison_type='PSSM',  # or 'MAT' (Caution: Method NOT
                                        # benchmarked for 'MAT')
               similarity_flag=True,    # The score matrix is not rescaled
               substitution=True,       # The BLOSUM62 substitution values are
                                        # multiplied to the corr. coef.
               smooth_prof_weight=10.0) # For mixing data with priors

    #write out aligned profiles (MSA)
    aln.write(file='HB_ALI_OUT_HB', alignment_format='PIR')

if __name__ == '__main__':
    try:
        run()
    except Exception as detail:
        print("Exited with error:", str(detail))
        raise
    print("Completed successfully")
