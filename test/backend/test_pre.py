import unittest
import salign
import saliweb.test
import saliweb.backend
import os
import re
import StringIO
import py_compile
import bsddb.db

class PreProcessTests(saliweb.test.TestCase):
    """Check preprocessing functions"""

    def assertScriptCompiles(self, script):
        """Make sure the given script is valid Python syntax"""
        t = saliweb.test.RunInTempDir()
        open('test.py', 'w').write(script)
        py_compile.compile('test.py', doraise=True)

    def test_read_parameters_file(self):
        """Check read_parameters_file function"""
        yaml = "tool: 1s_sese"
        p = salign.read_parameters_file(StringIO.StringIO(yaml))
        self.assertEqual(p, {'tool': '1s_sese'})

    def test_onestep_sese_pasted(self):
        """Test onestep_sese function with pasted sequences"""
        inp = {'1D_open_sese': -200, '1D_elong_sese': -300,
               'upld_pseqs': 2, 'align_type': 'tree', 'overhangs': 2,
               'improve': 'True', 'gap-gap_score': 100, 'gap-res_score': 200}
        p = salign.onestep_sese(inp, 'seqs', False)
        self.assertScriptCompiles(p)
        self.assert_(re.search("aln = alignment\(env, file='pasted_seqs.pir',.*"
                               "aln\.salign\(.*"
                               "alignment_type = 'tree',.+"
                               "gap_penalties_1d = \(\-200.\d+, \-300.\d+\),\W+"
                               "gap_gap_score = 100.\d+,\W+"
                               "gap_residue_score = 200.\d+,\W+"
                               "overhang = 2,\W+"
                               "improve_alignment = True,.*"
                               "aln\.write\(file='seq\-seq_out\.ali'", p,
                               re.DOTALL | re.MULTILINE),
                     "Python script does not match regex: " + p)

        # Check adv mode
        inp['1D_open_usr'] = 'Default'
        inp['1D_elong_usr'] = 'Default'
        p = salign.onestep_sese(inp, 'seqs', True)
        self.assertEqual(inp['1D_open'], -200.0)
        self.assertEqual(inp['1D_elong'], -300.0)
        inp['1D_open_usr'] = 100.0
        inp['1D_elong_usr'] = 300.0
        p = salign.onestep_sese(inp, 'seqs', True)
        self.assertEqual(inp['1D_open'], 100.0)
        self.assertEqual(inp['1D_elong'], 300.0)

    def test_onestep_sese_uploaded(self):
        """Test onestep_sese function with uploaded seq-seq alignments"""
        def make_uploads(d):
            b = bsddb.db.DB()
            b.open('upl_files.db', dbtype=bsddb.db.DB_HASH,
                   flags=bsddb.db.DB_CREATE | bsddb.db.DB_TRUNCATE)
            for key, value in d.items():
                b[key] = value

        inp = {'1D_open_sese': -200, '1D_elong_sese': -300,
               'upld_pseqs': 0, 'align_type': 'tree', 'overhangs': 2,
               'improve': 'True', 'gap-gap_score': 100, 'gap-res_score': 200}
        t = saliweb.test.RunInTempDir()

        make_uploads({'test.ali': 'pir-2-se'})
        p = salign.onestep_sese(inp, 'seqs', False)
        self.assertScriptCompiles(p)
        self.assert_(re.search("aln = alignment\(env, file='upload/test.ali', "
                               "align_codes='all', alignment_format= 'pir'", p,
                               re.DOTALL | re.MULTILINE),
                     "Python script does not match regex: " + p)

        make_uploads({'t.ali': 'fasta-2-se'})
        p = salign.onestep_sese(inp, 'seqs', False)
        self.assertScriptCompiles(p)
        self.assert_(re.search("aln = alignment\(env, file='upload/t.ali', "
                               "align_codes='all', alignment_format= 'fasta'",
                               p, re.DOTALL | re.MULTILINE),
                     "Python script does not match regex: " + p)

    def test_sese_stse_topf_sese(self):
        """Test sese_stse_topf function in seq-seq mode"""
        inp = {'1D_open': -200, '1D_elong': -300, 'align_type': 'tree',
               'overhangs': 2, 'improve': 'True', 'gap-gap_score': 100,
               'gap-res_score': 200}

        # Check input/output alignment files
        p = salign.sese_stse_topf(inp, 'input.ali', 'MYFORMAT', 2, 'sese',
                                  'output.ali')
        self.assertScriptCompiles(p)
        self.assert_(re.search("aln = alignment\(env, file='input.ali',.*"
                               "alignment_format= 'MYFORMAT'\).*"
                               "aln.write\(file='output.ali', "
                               "alignment_format='PIR'\)", p,
                               re.DOTALL | re.MULTILINE),
                     "Python script does not match regex: " + p)

        p = salign.sese_stse_topf(inp, '', '', 2, 'sese', 'output.ali')
        self.assert_(re.search("aln = alignment\(env\)", p,
                               re.DOTALL | re.MULTILINE),
                     "Python script does not match regex: " + p)

        # Check automatic align type
        inp['align_type'] = 'automatic'
        p = salign.sese_stse_topf(inp, 'i.ali', 'PIR', 30, 'sese', 'o.ali')
        self.assertScriptCompiles(p)
        self.assert_(re.search("alignment_type = 'tree'", p,
                               re.DOTALL | re.MULTILINE),
                     "Python script does not match regex: " + p)

        p = salign.sese_stse_topf(inp, 'i.ali', 'PIR', 31, 'sese', 'o.ali')
        self.assertScriptCompiles(p)
        self.assert_(re.search("alignment_type = 'progressive'", p,
                               re.DOTALL | re.MULTILINE),
                     "Python script does not match regex: " + p)

        # Check dendrogram output
        inp['align_type'] = 'tree'
        p = salign.sese_stse_topf(inp, 'i.ali', 'PIR', 3, 'sese', 'o.ali')
        self.assert_(re.search("dendrogram_file='salign\.tree'", p,
                               re.DOTALL | re.MULTILINE),
                     "Python script does not match regex: " + p)

        p = salign.sese_stse_topf(inp, 'i.ali', 'PIR', 2, 'sese', 'o.ali')
        self.assertFalse(re.search("dendrogram_file\s.=", p,
                                   re.DOTALL | re.MULTILINE),
                         "Python script matches regex: " + p)

    def test_make_sge_script(self):
        """Check make_sge_script function"""
        s = salign.make_sge_script(saliweb.backend.SGERunner, 'myscript.py')
        self.assert_(isinstance(s, saliweb.backend.SGERunner),
                     "SGERunner not returned")


if __name__ == '__main__':
    unittest.main()
