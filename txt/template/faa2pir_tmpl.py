from __future__ import print_function
from modeller import *

def run():
    log.level(1, 0, 1, 1, 1)
    env = environ()

    aln = alignment(env, file='HB_ALIFILE_HB',
                    alignment_format='HB_ALIFORMAT_HB')
    aln.write(file='HB_ALI_OUT_HB', alignment_format='PIR')

if __name__ == '__main__':
    try:
        run()
    except Exception as detail:
        print("Exited with error:", str(detail))
        raise
    print("Completed successfully")
