import unittest
import salign
import saliweb.test
import json
import re

class Tests(saliweb.test.TestCase):
    def test_email_success_str_str(self):
        """Test email_success, str_str"""
        def send_user_email(subject, body):
            self.assert_(re.search('has been processed.*Quality score.*42.*63.*'
                                   'Thank you',
                                   body, re.MULTILINE|re.DOTALL),
                         "%s does not match regex" % body)
        j = self.make_test_job(salign.Job, 'RUNNING')
        j.send_user_email = send_user_email
        d = saliweb.test.RunInDir(j.directory)
        open('output.error', 'w').write("")
        with open('inputs.json', 'w') as fh:
            json.dump({'tool':'str_str'}, fh)
        open('email_info', 'w').write("OK|42|63\n")
        j.send_job_completed_email()

    def test_email_success(self):
        """Test email_success, not str_str"""
        def send_user_email(subject, body):
            self.assert_(re.search('has been processed.*Thank you',
                                   body, re.MULTILINE|re.DOTALL),
                         "%s does not match regex" % body)
        j = self.make_test_job(salign.Job, 'RUNNING')
        j.send_user_email = send_user_email
        d = saliweb.test.RunInDir(j.directory)
        open('output.error', 'w').write("")
        with open('inputs.json', 'w') as fh:
            json.dump({'tool':'seq_seq'}, fh)
        open('email_info', 'w').write("OK|42|63\n")
        j.send_job_completed_email()

    def test_email_failure(self):
        """Test email_failure"""
        def send_user_email(subject, body):
            self.assert_(re.search('did not complete.*due to error.*'
                                   'error1.*error2',
                                   body, re.MULTILINE|re.DOTALL),
                         "%s does not match regex" % body)
        j = self.make_test_job(salign.Job, 'RUNNING')
        j.send_user_email = send_user_email
        j.config.send_admin_email = send_user_email
        d = saliweb.test.RunInDir(j.directory)
        open('email_info', 'w').write("FAIL\nerror1\nerror2\n")
        j.send_job_completed_email()

    def test_postprocess_1step_ok(self):
        """Test postprocess of successful 1-step run"""
        j = self.make_test_job(salign.Job, 'RUNNING')
        d = saliweb.test.RunInDir(j.directory)
        open('output.error', 'w').write("")
        with open('inputs.json', 'w') as fh:
            json.dump({'tool':'str_str'}, fh)
        open('str-str.log', 'w').write(
               "Raw QUALITY_SCORE of the multiple alignment:  45.0\n"
               "QUALITY_SCORE (percentage)  : 24.5\n"
               "Completed successfully")
        j.postprocess()
        f = open('email_info').read()
        self.assertEqual(f, "OK|45.0|24.5 %\n")

    def test_postprocess_1step_noqscore(self):
        """Test postprocess of successful 1-step run, no q score"""
        j = self.make_test_job(salign.Job, 'RUNNING')
        d = saliweb.test.RunInDir(j.directory)
        open('output.error', 'w').write("")
        with open('inputs.json', 'w') as fh:
            json.dump({'tool':'str_str'}, fh)
        open('str-str.log', 'w').write("Completed successfully")
        j.postprocess()
        f = open('email_info').read()
        self.assertEqual(f, "OK|Warning: no quality score found!|"
                            "Warning: no percentage found!\n")

    def test_postprocess_1step_nolog(self):
        """Test postprocess of 1-step run, no log file"""
        j = self.make_test_job(salign.Job, 'RUNNING')
        d = saliweb.test.RunInDir(j.directory)
        open('output.error', 'w').write("")
        with open('inputs.json', 'w') as fh:
            json.dump({'tool':'str_str'}, fh)
        self.assertRaises(salign.MissingLogError, j.postprocess)

    def test_postprocess_1step_fail_noerrs(self):
        """Test postprocess of failed 1-step run, no Modeller errors"""
        j = self.make_test_job(salign.Job, 'RUNNING')
        d = saliweb.test.RunInDir(j.directory)
        open('output.error', 'w').write("")
        with open('inputs.json', 'w') as fh:
            json.dump({'tool':'str_str'}, fh)
        open('str-str.log', 'w').write("")
        j.postprocess()
        f = open('email_info').read()
        self.assert_(re.match('FAIL\|\|.*No MODELLER error codes were found',
                              f, re.MULTILINE|re.DOTALL),
                     "%s does not match regex" % f)

    def test_postprocess_1step_fail_custom(self):
        """Test postprocess of failed 1-step run with custom error message"""
        j = self.make_test_job(salign.Job, 'RUNNING')
        d = saliweb.test.RunInDir(j.directory)
        open('output.error', 'w').write("")
        with open('inputs.json', 'w') as fh:
            json.dump({'tool':'str_str'}, fh)
        open('str-str.log', 'w').write("fit2xyz_296E> Our custom error")
        j.postprocess()
        f = open('email_info').read()
        self.assert_(re.match('FAIL\|\|.*'
                       '=> The server could not find enough.*'
                       'Hopefully, the information above helps.*'
                       'fit2xyz_296E>\s*$',
                              f, re.MULTILINE|re.DOTALL),
                     "%s does not match regex" % f)

    def test_postprocess_1step_fail_generic(self):
        """Test postprocess of failed 1-step run with generic error message"""
        j = self.make_test_job(salign.Job, 'RUNNING')
        d = saliweb.test.RunInDir(j.directory)
        open('output.error', 'w').write("")
        with open('inputs.json', 'w') as fh:
            json.dump({'tool':'str_str'}, fh)
        open('str-str.log', 'w').write("something_999E> Our generic error")
        j.postprocess()
        f = open('email_info').read()
        self.assert_(re.match('FAIL\|\|.*'
                       'Information about the errors can be found.*'
                       'something_999E>\s*$',
                              f, re.MULTILINE|re.DOTALL),
                     "%s does not match regex" % f)

    def test_postprocess_2step_ok(self):
        """Test postprocess of successful 2-step run"""
        j = self.make_test_job(salign.Job, 'RUNNING')
        d = saliweb.test.RunInDir(j.directory)
        open('output.error', 'w').write("")
        with open('inputs.json', 'w') as fh:
            json.dump({'tool':'str_seq'}, fh)
        open('final_alignment.log', 'w').write(
               "Raw QUALITY_SCORE of the multiple alignment:  45.0\n"
               "QUALITY_SCORE (percentage)  : 24.5\n"
               "Completed successfully")
        open('seq-seq.log', 'w').write("Completed successfully")
        open('str-str.log', 'w').write("Completed successfully")
        j.postprocess()
        f = open('email_info').read()
        self.assertEqual(f, "OK|45.0|24.5 %\n")

    def test_postprocess_2step_nolog(self):
        """Test postprocess of 2-step run, missing intermediate logs"""
        j = self.make_test_job(salign.Job, 'RUNNING')
        d = saliweb.test.RunInDir(j.directory)
        open('output.error', 'w').write("")
        with open('inputs.json', 'w') as fh:
            json.dump({'tool':'str_seq'}, fh)
        open('final_alignment.log', 'w').write(
               "Raw QUALITY_SCORE of the multiple alignment:  45.0\n"
               "QUALITY_SCORE (percentage)  : 24.5\n"
               "Completed successfully")
        self.assertRaises(salign.MissingLogError, j.postprocess)

    def test_postprocess_import_failed(self):
        """Test postprocess, Modeller import failure"""
        j = self.make_test_job(salign.Job, 'RUNNING')
        d = saliweb.test.RunInDir(j.directory)
        open('output.error', 'w').write("ImportError: No module named modeller")
        self.assertRaises(salign.ModellerImportError, j.postprocess)

if __name__ == '__main__':
    unittest.main()
