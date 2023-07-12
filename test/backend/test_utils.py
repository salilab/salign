import unittest
import salign
import saliweb.test
import saliweb.backend

class DummyRunner(object):
    def __init__(self, script): self.script = script
    def set_sge_options(self, opts): self.opts = opts
    def set_sge_name(self, name): self.name = name

class Tests(saliweb.test.TestCase):

    def test_make_sge_script(self):
        """Check make_sge_script()"""
        r = salign.make_sge_script(DummyRunner, ["foo", "bar"], 'testjob')

    def test_run_mod(self):
        """Check run_mod() function"""
        m = salign.run_mod('test.py')
        self.assertEqual(m, 'python3 test.py > test.log')

    def test_make_onestep_script(self):
        """Check make_onestep_script()"""
        s = salign.make_onestep_script(DummyRunner, 'str_str', 'testjob')
        s = salign.make_onestep_script(DummyRunner, 'seq_seq', 'testjob')

    def test_make_twostep_script(self):
        """Check make_twostep_script()"""
        s = salign.make_twostep_script(DummyRunner, 'str_seq', 'testjob')
        s = salign.make_twostep_script(DummyRunner, 'seq_seq', 'testjob')

if __name__ == '__main__':
    unittest.main()
