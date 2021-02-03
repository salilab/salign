from __future__ import print_function
from modeller import *
import sys


def frange(start,end=None,inc=None):
#  "A range function that accepts floating point increments"

    if end == None:
        end = start + 0.0
        start = 0.0
    else:
        start +=0.0

    if inc == None:
        inc = 1.0

    count = int((end - start)/inc)
    if start + (count*inc) != end:
        count += 1


    L = [None,]*count
    for i in range(count):
        L[i] = start + i*inc

    return L


# -- Script that takes in user specified feature weights and gap_penalties_1d,
# -- given an input alignment
def salign_fw_gaps1(aln,fil,fw,ogp,egp):

    log.verbose
    env = Environ()
    env.io.atom_files_directory = ['HB_STR_DIR_HB']
# aln = Alignment(env)
# aln.append(file=fil, align_codes='all')
    nseg = 2


    L =  aln.salign(rms_cutoff=HB_RMS_CUTOFF_HB,
         normalize_pp_scores=False,
         rr_file='$(LIB)/as1.sim.mat', overhang=0,
         auto_overhang=True, overhang_auto_limit=5, overhang_factor=1,
         gap_penalties_1d=(ogp, egp),
   #     local_alignment=True, matrix_offset = -0.2,
         local_alignment=False, matrix_offset = -0.2,
         gap_penalties_3d=(0, 3), gap_gap_score=HB_GAP_GAP_HB, gap_residue_score=HB_GAP_RES_HB,
   #     write_weights=False, output_weights_file ='salign.wgt',
         HB_DND_FILE_HB
         alignment_type=HB_ALIGN_TYPE_HB,
         nsegm=nseg,
         feature_weights=fw,
         improve_alignment=HB_IMPROVE_HB, fit=HB_FIT_HB, write_fit=False , write_whole_pdb=HB_WHOLE_PDB_HB,
         output='ALIGNMENT QUALITY' )

    return L

# -- Script that takes in user specified feature weights and gap_penalties_3d,
# -- given an input alignment
def salign_fw_gaps3(aln,fil,fw,ogp3d,egp3d,wf):

    log.verbose
    env = Environ()
    env.io.atom_files_directory = ['HB_STR_DIR_HB']
# aln = Alignment(env)
# aln.append(file=fil, align_codes='all')
    nseg = 2
    ogp = ogp3d
    egp = egp3d


    L = aln.salign(rms_cutoff=HB_RMS_CUTOFF_HB,
         normalize_pp_scores=False,
         rr_file='$(LIB)/as1.sim.mat', overhang=0,
         auto_overhang=True, overhang_auto_limit=5, overhang_factor=1,
         gap_penalties_1d=(ogp, egp),
   #     local_alignment=True, matrix_offset = -0.2,
         local_alignment=False, matrix_offset = -0.2,
         gap_penalties_3d=(ogp3d, egp3d), gap_gap_score=HB_GAP_GAP_HB, gap_residue_score=HB_GAP_RES_HB,
   #     write_weights=False, output_weights_file ='salign.wgt',
         HB_DND_FILE_HB
         alignment_type=HB_ALIGN_TYPE_HB,
         nsegm=nseg,
         feature_weights=fw,
   #      improve_alignment=HB_IMPROVE_HB, fit=HB_FIT_HB, write_fit=wf,  write_whole_pdb=HB_WHOLE_PDB_HB,
         improve_alignment=HB_IMPROVE_HB, fit=HB_FIT_HB, write_fit=True,  write_whole_pdb=HB_WHOLE_PDB_HB,
         output='ALIGNMENT QUALITY' )

    return L

# -- Script that takes in user specified feature weights and gap_penalties_1d,
# -- given an input alignment
def salign_fw_local_gaps1(aln,fil,fw,ogp,egp,mat_off):

    log.verbose
    env = Environ()
    env.io.atom_files_directory = ['HB_STR_DIR_HB']
# aln = Alignment(env)
# aln.append(file=fil, align_codes='all')
    nseg = 2


    L =  aln.salign(rms_cutoff=HB_RMS_CUTOFF_HB,
         normalize_pp_scores=False,
         rr_file='$(LIB)/as1.sim.mat', overhang=0,
   #     auto_overhang=True, overhang_auto_limit=5, overhang_factor=1,
         gap_penalties_1d=(ogp, egp),
         local_alignment=True, matrix_offset = mat_off, matrix_offset_3d = -0.5,
   #     local_alignment=False, matrix_offset = -0.2,
         gap_penalties_3d=(0, 3), gap_gap_score=HB_GAP_GAP_HB, gap_residue_score=HB_GAP_RES_HB,
   #     write_weights=False, output_weights_file ='salign.wgt',
         HB_DND_FILE_HB
         alignment_type=HB_ALIGN_TYPE_HB,
         nsegm=nseg,
         feature_weights=fw,
         improve_alignment=HB_IMPROVE_HB, fit=HB_FIT_HB, write_fit=False ,
         output='ALIGNMENT QUALITY' )

    return L

# -- Script that takes in user specified feature weights and gap_penalties_3d,
# -- given an input alignment
def salign_fw_local_gaps3(aln,fil,fw,ogp3d,egp3d,mat_off,mat_off_3d,wf):

    log.verbose
    env = Environ()
    env.io.atom_files_directory = ['HB_STR_DIR_HB']
# aln = Alignment(env)
# aln.append(file=fil, align_codes='all')
    nseg = 2
    ogp = ogp3d
    egp = egp3d


    L = aln.salign(rms_cutoff=HB_RMS_CUTOFF_HB,
         normalize_pp_scores=False,
         rr_file='$(LIB)/as1.sim.mat', overhang=0,
   #     auto_overhang=True, overhang_auto_limit=5, overhang_factor=1,
         gap_penalties_1d=(ogp, egp),
         local_alignment=True, matrix_offset = mat_off, matrix_offset_3d = mat_off_3d,
   #     local_alignment=False, matrix_offset = -0.2,
         gap_penalties_3d=(ogp3d, egp3d), gap_gap_score=HB_GAP_GAP_HB, gap_residue_score=HB_GAP_RES_HB,
   #     write_weights=False, output_weights_file ='salign.wgt',
         HB_DND_FILE_HB
         alignment_type=HB_ALIGN_TYPE_HB,
         nsegm=nseg,
         feature_weights=fw,
   #      improve_alignment=HB_IMPROVE_HB, fit=HB_FIT_HB, write_fit=wf,
         improve_alignment=HB_IMPROVE_HB, fit=HB_FIT_HB, write_fit=True,
         output='ALIGNMENT QUALITY' )

    return L

def run():
    log.verbose
    env = Environ()
    env.io.atom_files_directory = ['HB_STR_DIR_HB']
    aln = Alignment(env)

    HB_SALIGN_STR_SEGM_HB

    aln.write(file='HB_ALI_OUT_HBIni', alignment_format='pir')
    fil = "HB_ALI_OUT_HBIni"

    opfile = "HB_ALI_OUT_HBMid"
    opfile2 = "HB_ALI_OUT_HB"

    #opfile = "salign_local_mid.ali"
    #opfile1 = "salign_local.pap"
    #opfile2 = "salign_local.ali"

    nejon = True
    poi = False
    win_ogp3d = None

    #log.verbose
    #env = Environ()
    #env.io.atom_files_directory = ['HB_STR_DIR_HB']


    # -- Iterating over values of gap penalties and nsegm
    qmax = 0.0
    nsegm = 2
    fw1=(1., 0., 0., 0., 1., 0.)
    fw2=(0., 1., 0., 0., 0., 0.)
    fw3=(0., 0., 0., 0., 1., 0.)

    # -- Iterating over gap penalties 1D to get initial alignments
    for ogp in frange(HB_OGP_1D_HB,1,HB_OGP_1D_STEP_HB):
        for egp in frange(HB_EGP_1D_HB,1,HB_EGP_1D_STEP_HB):
            for mo in frange(-3.0, -0.05, 0.3) :
                aln = Alignment(env)
                aln.append(file=fil, align_codes='all')
                try:
                    qwlty1 = salign_fw_local_gaps1(aln,fil,fw1,ogp,egp,mo)
                    if qwlty1.qscorepct >= qmax:
                        qmax = qwlty1.qscorepct
                        aln.write(file=opfile, alignment_format='PIR')
                        win_ogp = ogp
                        win_egp = egp
                        win_mo = mo
                    print("Qlty scrs", ogp,"\t",egp,"\t",qwlty1.qscorepct)
                except ModellerError as detail:
                    print("Set of parameters",fw1,ogp,egp,"resulted in the following error\t"+str(detail))
                del(aln)


    # -- Iterating over gap panelties 3D to get final alignments
    for ogp3d in frange(HB_OGP_3D_HB,HB_OGP_3D_ROOF_HB,1) :
        for egp3d in range (HB_EGP_3D_HB,HB_EGP_3D_ROOF_HB,1) :
            aln = Alignment(env)
            aln.append(file=opfile, align_codes='all')
            try:
                qwlty2 = salign_fw_gaps3(aln,opfile,fw2,ogp3d,egp3d,poi)
                if qwlty2.qscorepct >= qmax:
                    qmax = qwlty2.qscorepct
    #                  aln.write(file=opfile1, alignment_format='PAP')
                    aln.write(file=opfile2, alignment_format='PIR')
                    win_ogp3d = ogp3d
                    win_egp3d = egp3d
                print("Qlty scrs", ogp3d,"\t",egp3d,"\t",qwlty2.qscorepct)
            except ModellerError as detail:
                print("Set of parameters",fw2,ogp3d,egp3d,"resulted in the following error\t"+str(detail))
            del (aln)

    #print("final max quality = ",qmax)

    # -- try alternate initial alignments only if the qmax score is less than 70%

    # - ******** qmax threshold for additional iterations to be determined *******
    qmax_old = qmax
    if (qmax_old <= 70) :
    #  qmax = 0.0
        for ogp in frange(0.0,2.2,0.3):
            for egp in frange(0.1,2.3,0.3):
                for mo in frange (-3.0, -0.05, 0.3) :
                    aln = Alignment(env)
                    aln.append(file=fil, align_codes='all')
                    try:
                        qwlty1 = salign_fw_local_gaps1(aln,fil,fw3,ogp,egp,mo)
                        if qwlty1.qscorepct >= qmax:
                            qmax = qwlty1.qscorepct
                            aln.write(file=opfile, alignment_format='PIR')
                            win_ogp = ogp
                            win_egp = egp
                            win_mo = mo
                        print("Qlty scrs", ogp,"\t",egp,"\t",qwlty1.qscorepct)
                    except ModellerError as detail:
                        print("Set of parameters",fw3,ogp,egp,"resulted in the following error\t"+str(detail))
                    del(aln)

    # -- Iterating over gap panelties 3D to get final alignments
        for ogp3d in frange(HB_OGP_3D_HB,HB_OGP_3D_ROOF_HB,1) :
            for egp3d in range (HB_EGP_3D_HB,HB_EGP_3D_ROOF_HB,1) :

                aln = Alignment(env)
                aln.append(file=opfile, align_codes='all')
                try:
                    qwlty2 = salign_fw_gaps3(aln,opfile,fw2,ogp3d,egp3d,poi)
                    if qwlty2.qscorepct >= qmax:
                        qmax = qwlty2.qscorepct
    #                     aln.write(file=opfile1, alignment_format='PAP')
                        aln.write(file=opfile2, alignment_format='PIR')
                        win_ogp3d = ogp3d
                        win_egp3d = egp3d
                    print("Qlty scrs", ogp3d,"\t",egp3d,"\t",qwlty2.qscorepct)
                except ModellerError as detail:
                    print("Set of parameters",fw2,ogp3d,egp3d,"resulted in the following error\t"+str(detail))
                del (aln)

    print("final max quality = ",qmax)
    if win_ogp3d is None:
        raise ModellerError("Structure alignment failed")

    aln = Alignment(env)
    aln.append(file=opfile, align_codes = 'all')
    salign_fw_gaps3(aln,opfile,fw2,win_ogp3d,win_egp3d,nejon)

if __name__ == '__main__':
    try:
        run()
    except Exception as detail:
        print("Exited with error:", str(detail))
        raise
    print("Completed successfully")
