# align2d/align using salign
from __future__ import print_function
from modeller import *

def run():
    log.verbose()
    env = Environ()
    HB_STR_DIR_HB
    HB_READ_ALI_HB
    HB_SALIGN_STR_SEGM_HB

    aln.salign(rr_file='$(LIB)/as1.sim.mat',  # Substitution matrix used
    #          rr_file='$(LIB)/blosum62.mat',  # Substitution matrix used
               HB_ALIGN_BLOCK_HB
               alignment_type = HB_ALIGN_TYPE_HB,
               HB_MAX_GAP_HB
               HB_GAP_FCTN_HB
               HB_DND_FILE_HB
               feature_weights = (1., 0., 0., 0., 0., 0.),
               gap_penalties_1d = (HB_GAP_PEN_1D_HB),
               HB_GAP_PEN_2D_HB
               gap_gap_score = HB_GAP_GAP_HB,
               gap_residue_score = HB_GAP_RES_HB,
     #         similarity_flag = True, # Ensuring that the dynamic programming
                                       # matrix is not scaled to a
                                       # difference matrix
     #         similarity_flag = False,
               overhang = HB_OVERHANGS_HB,
               improve_alignment = HB_IMPROVE_HB,
               output='')

    aln.write(file=HB_ALI_OUT_HB, alignment_format='PIR')

if __name__ == '__main__':
    try:
        run()
    except Exception as detail:
        print("Exited with error:", str(detail))
        raise
    print("Completed successfully")
