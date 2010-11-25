import saliweb.backend

def sese_stse_topf(inputs, fin_alipath, seq_count, top_type):
    """Create script for seq-seq and str-seq"""
    script = """
# align2d/align using salign
                                   
from modeller import *
log.verbose()
env = environ()
"""
    # set vars specific for st-se or se-se
    if top_type == 'stse':
        ali_type = "progressive"
        str_dir = "env.io.atom_files_directory='%s'" % str_dir
        gap_fctn = "gap_function=True,"
        gap_pen_2D = "gap_penalties_2d=(%d,%d,%d,%d,%d,%d,%d,%d,%d)," \
                     % (inputs['2D_1'], inputs['2D_2'], inputs['2D_3'],
                        inputs['2D_4'], inputs['2D_5'], inputs['2D_6'],
                        inputs['2D_7'], inputs['2D_8'], inputs['2D_9'])
        align_block = "align_block=%d" % seq_count
        dnd_file = ''
        max_gap = "max_gap_length=%d," % inputs['max_gap']
    else: # seq-seq
        if top_type == 'sese_pdbs': # TODO
            pass
        else: # All ali entries, no need to parse PDBs for seqs
            str_dir = ''
        if inputs['align_type'] == 'automatic':
            if seq_count <= 30:
                ali_type = "tree"
            else:
                ali_type = "progressive"
        else:
             ali_type = inputs['align_type']
        if ali_type == "tree" and seq_count > 2:
            dnd_name = "salign.tree"
            dnd_file = "dendrogram_file='%s'" % dnd_name
        else:
            dnd_file = ""
        gap_fctn   = ''
        gap_pen_2D = ''
        align_block = ''
        max_gap = ''

    # common vars for str-seq and seq-seq
    gap_pen_1D = "%f, %f" % (inputs['1D_open'], inputs['1D_elong'])
    output_ali = "'output.ali'"
    read_ali_line = ''
    if fin_alipath != '':
        read_ali_line = "aln = alignment(env, file= '%s', " % fin_alipath
        read_ali_line += "align_codes='all', "
        read_ali_line += "alignment_format= '%s'" % fin_aliformat
    else:
        read_ali_line = "aln = alignment(env)"

    overhangs = inputs['overhangs']
    improve = inputs['improve']
    gap_gap_score = inputs['gap-gap_score']
    gap_res_score = inputs['gap-res_score']

    script += str_dir + "\n" + read_ali_line + "\n" + tf_str_segm + """
aln.salign(rr_file='$(LIB)/as1.sim.mat',  # Substitution matrix used
           %(align_block)s,
           alignment_type = '%(ali_type)s',
           %(max_gap)s
           %(gap_fctn)s
           %(dnd_file)s
           feature_weights = (1., 0., 0., 0., 0., 0.),
           gap_penalties_1d = (%(gap_pen_1D)s),
           %(gap_pen_2D)s
           gap_gap_score = %(gap_gap_score)f,
           gap_residue_score = %(gap_res_score)f,
           overhang = %(overhangs)d,
           improve_alignment = %(improve)s,
           output='')
aln.write(file=%(output_ali)s, alignment_format='PIR')
""" % locals()
    return script


def onestep_sese(inputs, entries, adv):
    """Main sub for one step seq-seq alignments"""

    if adv:
        if inputs['1D_open_usr'] == 'Default':
            inputs['1D_open'] = inputs['1D_open_sese']
        else:
            inputs['1D_open'] = inputs['1D_open_usr']
        if inputs['1D_elong_usr'] == 'Default':
            inputs['1D_elong'] = inputs['1D_elong_sese']
        else:
            inputs['1D_elong'] = inputs['1D_elong_usr']
    else:
        inputs['1D_open'] = inputs['1D_open_sese']
        inputs['1D_elong'] = inputs['1D_elong_sese']

    # get str segments if not only seqs: TODO
    # Arrange all uploaded files in hashes: TODO
    ali_files = {'pir':{}}
    ali_count = 0
    seq_count = 0
    # perform multiple tasks on ali files if not only strs
    if entries != 'strs':
        if inputs['upld_pseqs'] > 0:
            file_path = 'pasted_seqs.pir'
            ali_files['pir'][file_path] = 1
            ali_count += 1
            seq_count += inputs['upld_pseqs']
            fin_alipath = file_path
         # TODO if more than one ali file

    # Create script file
    return sese_stse_topf(inputs, fin_alipath, seq_count, 'sese')


class Job(saliweb.backend.Job):
    runnercls = saliweb.backend.SaliSGERunner

    def run(self):
        parameters = read_parameters_file(open('parameters.yaml'))
        tool = parameters['tool']
        if tool == '1s_sese':
            p = onestep_sese(parameters, 'seqs', False)
        else:
            raise NotImplementedError("Unsupported tool type")
        open('salign.py', 'w').write(p)


def get_web_service(config_file):
    db = saliweb.backend.Database(Job)
    config = saliweb.backend.Config(config_file)
    return saliweb.backend.WebService(config, db)

