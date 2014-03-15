import saliweb.backend
import anydbm
import os

def make_sge_script(runnercls, commands):
    script = """
date
hostname
module load modeller/9.13
%s
date
""" % "\n".join(commands)
    r = runnercls(script)
    r.set_sge_options("-o output.error -j y -l netappsali=1G -p -4 "
                      "-l h_rt=24:00:00 -r y -N salign")
    return r

def run_mod(scriptname):
    return "python %s > %s" % (scriptname, scriptname[:-3] + '.log')

def make_onestep_script(runnercls, tool):
    if tool == 'str_str':
        scriptname = 'str-str.py'
    else:
        scriptname = 'seq-seq.py'
    commands = [run_mod(scriptname)]
    return make_sge_script(runnercls, commands)

def make_twostep_script(runnercls, tool):
    if tool == 'str_seq':
        top_file1 = 'str-str.py'
        top_file2 = 'seq-seq.py'
        top_file3 = 'final_alignment.py'
        file2fuse_1 = 'str-str_out.ali'
        file2fuse_2 = 'seq-seq_out.ali'
        fuse_file = 'str-seq_fuse.ali'
    else: # 2 step seq-seq
        top_file1 = 'seq-seq1.py'
        top_file2 = 'seq-seq2.py'
        top_file3 = 'profile.py'
        file2fuse_1 = 'seq-seq_out1.ali'
        file2fuse_2 = 'seq-seq_out2.ali'
        fuse_file = 'prof_in.ali'
    commands = [run_mod(top_file1), run_mod(top_file2),
                "cat %s %s > %s" % (file2fuse_1, file2fuse_2, fuse_file),
                run_mod(top_file3)]
    return make_sge_script(runnercls, commands)

class Job(saliweb.backend.Job):
    runnercls = saliweb.backend.SaliSGERunner

    def run(self):
        tool = anydbm.open('inputs.db')['tool']
        if tool in ('str_str', '1s_sese'):
            return make_onestep_script(self.runnercls, tool)
        elif tool in ('2s_sese', 'str_seq'):
            return make_twostep_script(self.runnercls, tool)
        else:
            raise ValueError("Tool %s not recognized" % tool)

    def postprocess(self):
        self.check_log_files()

    def check_log_files():
        fh = open('email_info', 'w')
        print >> fh, "OK||"

    def send_job_completed_email(self):
        fh = open('email_info')
        email_info = fh.readline().rstrip('\r\n').split('|')
        if email_info[0] == 'OK':
            tool = anydbm.open('inputs.db')['tool']
            self.email_success(tool, email_info[1], email_info[2])
        else:
            self.email_failure(fh.read())

    def email_success(self, tool, q_score, q_score_percent):
        msg = "---------- SALIGN JOB ID %s ----------\n\n" % self.name + \
              "Your SALIGN job has been processed\n\n"
        if tool == 'str_str':
            msg += "Quality score of alignment: %s ( %s )\n\n" \
                   % (q_score, q_score_percent)
        msg += "Please click on hyperlink below to collect results.\n" \
               + self.url + "\nThank you for using SALIGN\n\n" \
               + "Please address questions and comments to:\n" \
               + "SALIGN web server administrator <%s>\n" \
                 % self.config.admin_email
        self.send_user_email("SALIGN job %s results" % self.name, msg)

    def email_failure(self, errors):
        msg = "---------- SALIGN JOB ID %s ----------\n\n" % self.name + \
              "Dear SALIGN user,\n\n" + \
              "Unfortunately, the SALIGN run did not complete " + \
              "successfully, due to error(s):\n\n" + errors
        msg += "Log files and further information about the MODELLER " \
               + "run can be found at\n" + self.url \
               + "\nPlease address questions and comments to:\n" \
               + "SALIGN web server administrator <%s>\n" \
                 % self.config.admin_email
        self.send_user_email("SALIGN job %s run error" % self.name, msg)

def get_web_service(config_file):
    db = saliweb.backend.Database(Job)
    config = saliweb.backend.Config(config_file)
    return saliweb.backend.WebService(config, db)
