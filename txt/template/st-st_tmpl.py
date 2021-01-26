# Structure-structure alignment input file.
from __future__ import print_function
from modeller import *

def run():
    log.verbose()
    env = Environ()
    env.io.atom_files_directory = 'HB_STR_DIR_HB'
    aln = Alignment(env)

    HB_SALIGN_STR_SEGM_HB

    # 1) get a sequence alignment and assess it.
    # 2) get a full SALIGN alignment and assess it (less of feature 2),
    #    to provide a better initial alignment for the final SALIGN alignment.
    for (_weights) in  ( ((1., 0., 0., 0., 1., 0.)),
                         ((1., 0.5, 1., 1., 1., 0.)) ):
        aln.salign(rms_cutoff=HB_RMS_CUTOFF_HB,
                   normalize_pp_scores=False,
                   rr_file='$(LIB)/as1.sim.mat',
                   auto_overhang=True, overhang_factor=1,
                   overhang_auto_limit=10,
                   gap_penalties_1d=(-450, -50),
                   gap_penalties_3d=(HB_OGP_3D_HB, HB_EGP_3D_HB),
                   gap_gap_score=HB_GAP_GAP_HB, gap_residue_score=HB_GAP_RES_HB,
                   alignment_type=HB_ALIGN_TYPE_HB,
                   max_gap_length=HB_MAX_GAP_HB,
                   feature_weights=_weights,
                   improve_alignment=True, fit=True, write_fit=False,
                   write_whole_pdb=True, output='ALIGNMENT QUALITY')

    # get the 2nd generation SALIGN alignment and assess it
    aln.salign(rms_cutoff=HB_RMS_CUTOFF_HB,
               normalize_pp_scores=False,
               rr_file='$(LIB)/as1.sim.mat',
               overhang=HB_OVERHANGS_HB,
               gap_penalties_1d=(HB_OGP_1D_HB, HB_EGP_1D_HB),
               gap_penalties_3d=(HB_OGP_3D_HB, HB_EGP_3D_HB),
               gap_gap_score=HB_GAP_GAP_HB, gap_residue_score=HB_GAP_RES_HB,
               alignment_type=HB_ALIGN_TYPE_HB, HB_DND_FILE_HB
               max_gap_length=HB_MAX_GAP_HB,
               feature_weights=(HB_FEAT_WEIGHTS_HB), HB_WEIGHT_MTX_HB
               improve_alignment=HB_IMPROVE_HB, fit=HB_FIT_HB, write_fit=True,
               write_whole_pdb=HB_WHOLE_PDB_HB, output='ALIGNMENT QUALITY')

    aln.write(file='HB_ALI_OUT_HB', alignment_format='PIR')

if __name__ == '__main__':
    try:
        run()
    except Exception as detail:
        print("Exited with error:", str(detail))
        raise
    print("Completed successfully")
