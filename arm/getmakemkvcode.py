import os
from robobrowser import RoboBrowser


def grabcode():

    def get_code():
        base_code = '<div class="codetitle"><b>Code:</b></div><div class="codecontent">'
        global i, pageStr, strLength
        br = RoboBrowser()
        br.open('https://www.makemkv.com/forum2/viewtopic.php?f=5&t=1053')
        pageStr = str(br.parsed())
        i = 1
        beg = pageStr.find(base_code)

        strLength = len(base_code)

        while True:
            code = pageStr[beg + strLength:beg + strLength + i]
            print(code)

            if pageStr[beg + strLength:beg + strLength + i].find("<") != -1:
                return code[:-1]

            i = i + 1
    makemkvcode = get_code()
    print(makemkvcode)
    os.system('rm /home/arm/.MakeMKV/settings.conf')
    os.system('echo "{}" >> /home/arm/.MakeMKV/settings.conf'.format('app_Key = "makemkvcode"'))
