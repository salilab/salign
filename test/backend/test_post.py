import unittest
import salign
import saliweb.test
import anydbm
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
        db = anydbm.open('inputs.db', 'n')
        db['tool'] = 'str_str'
        db.close()
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
        db = anydbm.open('inputs.db', 'n')
        db['tool'] = 'seq_seq'
        db.close()
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
        d = saliweb.test.RunInDir(j.directory)
        open('email_info', 'w').write("FAIL\nerror1\nerror2\n")
        j.send_job_completed_email()

if __name__ == '__main__':
    unittest.main()
