import unittest
import salign
import saliweb.test
import json

class JobTests(saliweb.test.TestCase):
    def test_run(self):
        """Test run method"""
        for tool in ('str_str', '1s_sese', '2s_sese', 'str_seq'):
            j = self.make_test_job(salign.Job, 'RUNNING')
            d = saliweb.test.RunInDir(j.directory)
            with open('inputs.json', 'w') as fh:
                json.dump({'tool':tool}, fh)
            j.run()
            del d

    def test_run_bad_tool(self):
        """Test run method with bad tool"""
        j = self.make_test_job(salign.Job, 'RUNNING')
        d = saliweb.test.RunInDir(j.directory)
        with open('inputs.json', 'w') as fh:
            json.dump({'tool':'garbage'}, fh)
        self.assertRaises(ValueError, j.run)

if __name__ == '__main__':
    unittest.main()
