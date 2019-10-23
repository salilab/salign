from __future__ import print_function
import saliweb.backend
try:
    import anydbm  # python2
except ImportError:
    import dbm as anydbm  # python3
import os
import re

class MissingLogError(Exception):
    pass

class ModellerImportError(Exception):
    pass

def make_sge_script(runnercls, commands):
    script = """
date
hostname
module load modeller/9.23
%s
date
""" % "\n".join(commands)
    r = runnercls(script)
    r.set_sge_options("-o output.error -j y -l netappsali=1G -p -4 "
                      "-l h_rt=72:00:00 -r y -N salign")
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
        if tool in (b'str_str', b'1s_sese'):
            return make_onestep_script(self.runnercls, tool)
        elif tool in (b'2s_sese', b'str_seq'):
            return make_twostep_script(self.runnercls, tool)
        else:
            raise ValueError("Tool %s not recognized" % tool)

    def postprocess(self):
        self.check_import_failure()
        tool = anydbm.open('inputs.db')['tool']
        self.check_log_files(tool)

    def check_import_failure(self):
        """Fail the job if Modeller could not be imported"""
        with open("output.error") as fh:
            contents = fh.read()
        if 'ImportError' in contents:
            raise ModellerImportError("Could not import Modeller")

    def check_line_error(self, line, errorcodes):
        if 'E>' in line:
            for word in line.split():
                if 'E>' in word:
                    errorcodes[word] = line

    def check_intermediate_logs(self, intmed_logs, errorcodes):
        """If intermediate logs should exist, check that they do and
           look for errors"""
        compl_succ_intmed = 0
        intmedlogcount = 0
        for intmed_log in intmed_logs:
            if os.path.exists(intmed_log):
                for line in open(intmed_log):
                    self.check_line_error(line, errorcodes)
                    if "Completed successfully" in line:
                        compl_succ_intmed += 1
                intmedlogcount += 1
        if len(intmed_logs) > 0 and intmedlogcount == 0:
            raise MissingLogError("No intermediate log files exist")
        return compl_succ_intmed

    def check_mod_log(self, mod_log, intmed_logs, errorcodes):
        """Find quality score and possible errors in main MODELLER log file"""
        q_score_re = re.compile("Raw QUALITY_SCORE of the multiple "
                                "alignment\s*:\s*([\d\.-]+)\s*$")
        q_score_pct_re = re.compile("QUALITY_SCORE \(percentage\)\s*:"
                                    "\s*([\d\.-]+)\s*$")
        compl_succ = 0
        q_score = "Warning: no quality score found!"
        q_score_percent = "Warning: no percentage found!"
        if os.path.exists(mod_log):
            for line in open(mod_log):
                self.check_line_error(line, errorcodes)
                if "Completed successfully" in line:
                    compl_succ += 1
                if "Raw QUALITY_SCORE" in line:
                    q_score = q_score_re.search(line).group(1)
                if "QUALITY_SCORE (percentage)" in line:
                    q_score_percent = q_score_pct_re.search(line).group(1) \
                                      + " %"
        elif len(intmed_logs) == 0:
            raise MissingLogError("No MODELLER log file exists")
        return compl_succ, q_score, q_score_percent

    def check_log_files(self, tool):
        # set path(s) to log file(s)
        intmed_logs = {b'str_str': [], b'1s_sese': [],
                       b'2s_sese': ['seq-seq1.log', 'seq-seq2.log'],
                       b'str_seq': ['seq-seq.log', 'str-str.log']}[tool]
        mod_log = {b'str_str': 'str-str.log', b'1s_sese': 'seq-seq.log',
                   b'2s_sese': 'profile.log',
                   b'str_seq': 'final_alignment.log'}[tool]
        errorcodes = {}
        compl_succ_intmed = self.check_intermediate_logs(intmed_logs,
                                                         errorcodes)
        compl_succ, q_score, q_score_percent = self.check_mod_log(mod_log,
                                                   intmed_logs, errorcodes)

        if compl_succ == 1 and compl_succ_intmed == len(intmed_logs):
            self.report_logs_ok(q_score, q_score_percent)
        else:
            self.report_log_failure(errorcodes)

    def report_logs_ok(self, q_score, q_score_percent):
        with open('email_info', 'w') as fh:
            print("OK|%s|%s" % (q_score, q_score_percent), file=fh)

    def report_log_failure(self, errorcodes):
        customerrors = {
           'fit2xyz_296E>': ' => The server could not find enough equivalent positions between the structures to carry out a successful alignment. This could be due to incorrectly specified structure segments in the input, or the structures may not be similar enough to align accurately. Please see the SALIGN Help pages for instructions on specifying structure segments.',
           'read_al_375E>': ' => The server recognized at least one sequence of an incorrect format, including disallowed characters in the sequence. This could be the result of pasting a sequence with a header. If so, please either paste sequences without headers, or upload sequences with headers using the upload button. Alternatively, the error could be due to a sequence with lower-case characters. If so, please submit as upper-case instead.',
           'rdpdb___303E>': ' => The server recognized at least one incorrectly specified PDB segment. Make sure that the requested chains and residues exist in the PDB, and that these were properly specified in the input page. See SALIGN help for details on how to specify PDB segments.',
           'pdbnam_____E>': ' => The requested PDB file was not found. Make sure that the requested PDB code exists in the PDB, and that you entered the PDB codes correctly. For more on entering PDB codes, see the SALIGN Help.',
           'parse_pir__E>': ' => The server detected an incorrectly formatted MODELLER PIR file. For information on alignment file formats, see SALIGN help.',
           'readlinef__E>': ' => The most likely reason for this error is that you uploaded an archive of a folder containing files. Archives (.zip and .tar.gz) should contain all files in the top level, and not within a folder. Thus, when preparing these, make sure to archive all desired files directly, not a folder containing the files.'
        }

        with open('email_info', 'w') as fh:
            print("FAIL||", file=fh)
            custom = False
            for err, line in errorcodes.items():
                if err in customerrors:
                    print(customerrors[err], file=fh)
                    custom = True
            if errorcodes:
                if custom:
                    print("\nHopefully, the information above helps solve the problem. However, if more information is needed, please search the MODELLER log file for the following error codes for more information:\n\n", file=fh)
                else:
                    print("Information about the errors can be found in the MODELLER log file. Normally, you will find the error at the bottom of the log file, or you can search it for the following error codes:\n\n", file=fh)
                print("\n".join(errorcodes.keys()), file=fh)
            else:
                print("No MODELLER error codes were found, however the log file does not indicate successful completion. Usually this means that your job ran out of time (in which case you could try a smaller alignment, or download the script files and run it on your own computer). Please see if the log file provides more information.\n", file=fh)

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
        if tool == b'str_str':
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
        msg += "\nLog files and further information about the MODELLER " \
               + "run can be found at\n" + self.url \
               + "\n\nPlease address questions and comments to:\n" \
               + "SALIGN web server administrator <%s>\n" \
                 % self.config.admin_email
        subject = "SALIGN job %s run error" % self.name
        self.send_user_email(subject, msg)
        self.config.send_admin_email(subject, msg)

def get_web_service(config_file):
    db = saliweb.backend.Database(Job)
    config = saliweb.backend.Config(config_file)
    return saliweb.backend.WebService(config, db)
