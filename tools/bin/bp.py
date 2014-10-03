#!/usr/bin/env python

# (c) Copyright 2014 Hewlett-Packard Development Company, L.P.
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.
#
# This file was autogenerated by the transformation.py script

import sys
import getopt
import urllib2
from urlparse import urlparse
import re
import logging
import yaml
import os
import subprocess
import distutils.spawn
import string
import datetime
import time
import tempfile

# Defining defaults

# By default, we implements the required source yaml section. This can be update by a flag --source (NOT YET IMPLEMENTED)
SOURCES = "modules"
BRANCH = 'master'
TEST_BOX = ''
BLUEPRINT_REF_PATH = os.path.join(os.sep, 'usr', 'lib', 'forj', 'blueprints')
BLUEPRINT_REPOS_DIR = os.path.join(os.sep, 'opt', 'config', 'production', 'blueprints')
GIT_REPOS_DIR = os.path.join(os.sep, 'opt', 'config', 'production', 'git')


def help():
    print 'bp --install <url|bp-name> [--branch <branchName>] [--debug] [-v]'


def load_bp(bp_element):
    "load_bp function read from a file or from an url, the blueprint yaml document. It returns the blueprint data in dict object."
    dUrl = urlparse(bp_element)
    re_filename = re.compile('^[a-zA-Z0-9]*$')
    if dUrl.scheme == '' and re_filename.match(bp_element):  # Need to build the url with forj-oss link by default.
        # Disabled, until our catalog service is available.
        # dUrl=ParseResult('http','catalog.forj.io','/master/'+bp_element+'-master.yaml','','','')
        # bp_element=dUrl.geturl()
        # logging.debug('Use default internet FORJ catalog: ' + bp_element)
        sBP_file = os.path.join(os.sep, 'opt', 'config', 'production', 'git', 'maestro', 'blueprint_samples', bp_element + '-master.yaml')
        if os.path.exists(sBP_file):
            bp_element = sBP_file
            logging.debug('Use default internet FORJ catalog: ' + bp_element)
        else:
            logging.error('Unable to found "' + bp_element + '" from /opt/config/production/git/maestro/blueprint_samples/*-master.yaml. aborted. ')
            sys.exit(1)
# End of disabled section.
    if dUrl.scheme == '':
        try:
            fYaml_hdl = open(bp_element)
        except IOError, e:
            logging.error('Unable to open %s: %s', dUrl.path, e.strerror)
            return 0
    else:
        fYaml_req = urllib2.Request(bp_element)
        try:
            fYaml_hdl = urllib2.urlopen(fYaml_req)
        except urllib2.URLError, e:
            logging.error('Unable to contact the url "' + bp_element + '" : ' + e.reason)
            sys.exit(1)
        except urllib2.URLError, e:
            logging.error('Unable to retrieve the blueprint from the url "' + bp_element + '" : ' + e.code)
            sys.exit(1)

    fYaml = yaml.load(fYaml_hdl)
    logging.debug(yaml.dump(fYaml))
    return [fYaml, bp_element]


def cmd_call(tool, aCMD):
    try:
        logging.debug('Running : ' + string.join(aCMD, ' '))
        # Returns /tmp on ubuntu
        sys_tmp = tempfile.gettempdir()
        log_file = os.path.join(sys_tmp, tool + ".log")
        f = open(log_file, "wb")
        iCode = subprocess.call(aCMD, stdout=f)
    except OSError, e:
        logging.error('%s: "%s" fails with return code: %d (%s)', tool, string.join(aCMD, ' '), iCode, e.message)


def check_call(aCMD):
    if (sys.version_info[0] == 2 and sys.version_info[1] < 7):
        try:
            output = subprocess.Popen(aCMD, stderr=subprocess.STDOUT,stdout=subprocess.PIPE).communicate()[0]
            logging.debug('Checking : %s\n%s', string.join(aCMD, ' '), output)
        except subprocess.CalledProcessError as oErr:
            iCode = oErr.returncode
            return {'output': output, 'iCode': iCode}
    else:
        try:
            output = subprocess.check_output(aCMD, stderr=subprocess.STDOUT)
            logging.debug('Checking : %s\n%s', string.join(aCMD, ' '), output)
        except subprocess.CalledProcessError as oErr:
            iCode = oErr.returncode
            return {'output': output, 'iCode': iCode}
    return {'output': output, 'iCode': 0}


def git_clone(sRepo):
    """
    git_clone(sRepo{'git','cloned-to','src-repo','branch','puppet-extra-modules'): Execute a git clone of an url.
    sRepo is a data structure which contains: [] means optional.
    git                    : url to clone
    src-repo               : Directory name of the cloned repo.
    [cloned-to]            : Optional. Path where to store the cloned repo.
                             default: /opt/config/production/git
    [branch]               : Optional. Git branch to clone.
                             default: 'master' (BRANCH)
    [puppet-extra-modules] : If set, will consider this repository as publishing additional puppet modules

    if the repository cloned is the main puppet blueprint module code, the <repo>/puppet/modules will be linked to
    /opt/config/production/blueprints/<repo-name aka src-repo>
    otherwise, if puppet-extra-modules is set, a link from <puppet-extra-modules> path will be created in
    /opt/config/production/puppet/modules/<repo-name aka src-repo>
    This link is considered only if <puppet-extra-modules> directory contains at least one module containing 'manifests' as sub directory
    """

    global TEST_BOX

    GIT = distutils.spawn.find_executable('git')
    url = sRepo['git']
    to = (sRepo['cloned-to'] if 'cloned-to' in sRepo else GIT_REPOS_DIR)
    gitbranch = (sRepo['branch'] if 'branch' in sRepo else BRANCH)
    name = sRepo['src-repo']
    if 'puppet-extra-modules' in sRepo:
        extra_mods = sRepo['puppet-extra-modules']
        mods = ''
    else:
        extra_mods = ''
        mods = os.path.join(to, name, 'puppet', 'modules')
    logging.debug("extra_mods => '%s' , mods => '%s'", extra_mods, mods)

    sBlueprint_path = os.path.join(os.sep, 'opt', 'config', 'production', 'blueprints')
    sAdd_mod_path = os.path.join(os.sep, 'opt', 'config', 'production', 'puppet', 'modules')

    logging.info("GIT: Cloning '%s' to '%s'", url, to)
    if not os.path.isdir(to) or not os.access(to, os.W_OK):
        logging.error("'%s' doesn't exist or is not writable. Please check. git clone aborted.", to)
        return
    if not os.access(GIT, os.X_OK):
        logging.error("'%s' is not executable. Is git installed???", GIT)
        return

    # Define possible actions:
    sAction = {'rename': False}  # Rename the directory to clone over there
    sAction['clone'] = False  # Do the clone
    sAction['checkout branch'] = False  # The current branch have to be changed to the existing one
    sAction['create branch'] = False  # The current branch have to be changed to a new one to create.
    sAction['branch attach'] = False  # The wanted branch is not attached
    sAction['remote rename'] = False  # The remote exist but is incorrect. A rename is required.
    sAction['remote create'] = False  # The remote do not exist. Create it
    sAction['remote set'] = False  # The remote url is not set

    if os.path.exists(os.path.join(to, name)):
        # Series of checks: Is a dir? Is a git repository? Is correct branch? Is remote attached and is Origin? Is Origin set to the url?
        if not os.path.isdir(os.path.join(to, name)):
            # not a dir: cloning.
            logging.debug('%s not a dir: cloning.', os.path.join(to, name))
            sAction['clone'] = True  # Do the clone
        elif not os.access(os.path.join(to, name), os.R_OK | os.X_OK):
            # not accessible: Rename it and clone.
            logging.debug('%s not accessible: Renaming it and cloning.', os.path.join(to, name))
            sAction['rename'] = True  # Rename the directory to clone over there
            sAction['clone'] = True  # Do the clone
        else:
            os.chdir(os.path.join(to, name))
            oCheckResult = check_call([GIT, 'rev-parse', '--git-dir'])
            iCode = oCheckResult['iCode']
            output = oCheckResult['output']
            if iCode != 0:
                # Not a git repository
                logging.debug('%s Not a git repository: Renaming it and cloning.\nreturn code : %s\noutput:\n%s', os.path.join(to, name), iCode, output)
                sAction['rename'] = True  # Rename the directory to clone over there
                sAction['clone'] = True  # Do the clone
            else:
                # Checking the branch configuration
                oReBranch = re.compile('\*\s([\w-]+)\s+\w+\s+')
                oCheckResult = check_call([GIT, 'branch', '-vv'])
                iCode = oCheckResult['iCode']
                output = oCheckResult['output']
                oResult = oReBranch.search(output)
                if oResult.group(1) != gitbranch:
                    if re.search('[* ]\s+' + gitbranch + '\s+', output) is not None:
                        sAction['checkout branch'] = True  # The current branch have to be changed to the existing one
                    else:
                        sAction['create branch'] = True  # The current branch have to be changed to a new one to create.
                oReBranch = re.compile('\s+(' + gitbranch + ')+\s.*\[([\w-]+)/([\w-]+)')
                oResult = oReBranch.search(output)
                if iCode != 0:
                    # Error in getting branch name. So decide to simply rename and clone again.
                    logging.debug('Error in getting branch name. So decide to simply rename and clone again.\nreturn code : %s\noutput:\n%s', iCode, output)
                    sAction['rename'] = True  # Rename the directory to clone over there
                    sAction['clone'] = True  # Do the clone
                elif not sAction['create branch'] and oResult is None:  # Branch not attached:
                    sAction['branch attach'] = True  # The wanted branch is not attached. But right now, we do not know if remote exists or not.
                elif not sAction['create branch'] and oResult.group(2) != 'origin':  # Branch attached to the wrong remote
                    sAction['branch attach'] = True  # The wanted branch is not attached. But right now, we do not know if remote exists or not.
                elif not sAction['create branch'] and oResult.group(3) != gitbranch:  # Branch attached to origin but wrong remote branch.
                    sAction['branch attach'] = True  # The wanted branch is not attached. But right now, we do not know if remote exists or not.
                if iCode == 0 and not sAction['remote create']:
                    # Checking the remote configuration
                    oReBranch = re.compile('origin\s+(.*)\s+\(fetch')
                    oCheckResult = check_call([GIT, 'remote', '-v'])
                    iCode = oCheckResult['iCode']
                    output = oCheckResult['output']
                    oResult = oReBranch.search(output)
                    if iCode != 0:
                        # Error in getting remote name. So decide to simply rename and clone again.
                        logging.debug('Error in getting branch name. So decide to simply rename and clone again.\nreturn code : %s\noutput:\n%s', iCode, output)
                        sAction['rename'] = True  # Rename the directory to clone over there
                        sAction['clone'] = True  # Do the clone
                    elif oResult is None:
                        sAction['remote create'] = True
                        sAction['remote rm'] = True
                    elif oResult.group(1) != url:
                        sAction['remote set'] = True
    else:
        # simply cloning
        sAction['clone'] = True

    logging.debug("Actions:")
    logging.debug(sAction)

    # Do action on git repo as described by sAction
    if sAction['rename']:  # Rename the directory to clone over there
        cmd_call('git_clone', ['rm', '-fr', os.path.join(to, name) + '.bak'])
        os.rename(os.path.join(to, name), os.path.join(to, name) + '.bak')
    if sAction['clone']:  # Do the clone
        os.chdir(to)
        cmd_call('git_clone: git', [GIT, 'clone', url, name, '-b', gitbranch])
    os.chdir(os.path.join(to, name))
    if sAction['checkout branch']:  # The current branch have to be changed.
        cmd_call('git_clone', [GIT, 'checkout', gitbranch])
    if sAction['create branch']:  # The current branch have to be changed.
        cmd_call('git_clone', [GIT, 'checkout', '-b', gitbranch])
    if sAction['remote rename']:  # The remote exist but is incorrect. A rename is required.
        # TODO VERIFY WITH CHRISS, remote-output doesnt exist
        # if re.search('\n?origin-bak\s+', remote-output) is not None:
        #     cmd_call('git_clone', [GIT, 'remote', 'rm', 'origin-bak'])
        cmd_call('git_clone', [GIT, 'remote', 'rename', 'origin', 'origin-bak'])
    if sAction['remote create']:  # The remote do not exist. Create it
        cmd_call('git_clone', [GIT, 'remote', 'add', 'origin', url])
        cmd_call('git_clone', [GIT, 'fetch', 'origin'])
    if sAction['remote set']:  # The remote url is not set
        cmd_call('git_clone', [GIT, 'remote', 'set-url', 'origin', url])
    if sAction['branch attach']:  # The wanted branch is not attached
        cmd_call('git_clone', [GIT, 'branch', '--set-upstream', gitbranch, 'origin/' + gitbranch])
    cmd_call('git_clone: git', ['chown', '-R', 'puppet:puppet', os.path.join(to, name)])

    if TEST_BOX != "":
        # TODO: Re-organize to have multiple test-box repos to test.
        reObj = re.compile('(.*):(.*)')
        oResult = reObj.search(TEST_BOX)
        if oResult.group(1) == name:  # Need test-box on this repo.
            logging.info("test-box: Configuring repo '%s'...", name)
            gitbranch = oResult.group(2)
            # Checking the branch configuration
            oReBranch = re.compile('\*\s([\w-]+)\s+\w+\s+')
            oCheckResult = check_call([GIT, 'branch', '-vv'])
            iCode = oCheckResult['iCode']
            output = oCheckResult['output']
            oResult = oReBranch.search(output)
            if oResult.group(1) != gitbranch:
                cmd_call('git_clone: git', [GIT, 'remote', 'add', 'testing', '/home/ubuntu/git/' + name + '.git'])
                if not os.path.exists('/home/ubuntu/git/' + name + '.git'):
                    logging.info('/home/ubuntu/git/' + name + '.git does\'exist. waiting test-box to occurs from your workstation.')
                    logging.info('build.sh: test-box-repo=%s', name)
                    while not os.path.exists('/home/ubuntu/git/' + name + '.git'):
                        time.sleep(5)
                os.chdir('/home/ubuntu/git/' + name + '.git')
                # Checking the branch configuration
                oReBranch = re.compile('[*\s]*([\w-]+)\s+\w+\s+')
                oCheckResult = check_call([GIT, 'branch', '-vv'])
                oResult = oReBranch.search(oCheckResult['output'])
                if oResult is None or oResult.group(1) != gitbranch:
                    logging.info('test-box: %s is missing from \'%s\'', gitbranch, '/home/ubuntu/git/' + name + '.git')
                    time.sleep(5)
                    oCheckResult = check_call([GIT, 'branch', '-vv'])
                    oResult = oReBranch.search(oCheckResult['output'])
                    while oResult is None or oResult.group(1) != gitbranch:
                        time.sleep(5)
                        oCheckResult = check_call([GIT, 'branch', '-vv'])
                        oResult = oReBranch.search(oCheckResult['output'])
                os.chdir(os.path.join(to, name))
                cmd_call('git_clone: git', [GIT, 'fetch', 'testing'])
                cmd_call('git_clone: git', [GIT, 'branch', gitbranch])
                cmd_call('git_clone', [GIT, 'branch', '--set-upstream', gitbranch, 'testing/' + gitbranch])
                cmd_call('git_clone', [GIT, 'checkout', gitbranch])
                cmd_call('git_clone', [GIT, 'pull'])
            logging.info('test-box: repo \'%s\' is configured with branch \'%s\'', name, gitbranch)

    # Links managements to blueprints/ or puppet/modules/
    if mods != '' and os.path.exists(mods):
        logging.debug("mods not empty, performing cmd: ln -sf '%s' '%s'", mods, os.path.join(sBlueprint_path, name))
        if os.path.lexists(os.path.join(sBlueprint_path, name)):
            cmd_call('git_clone: rm', ['rm', '-fr', os.path.join(sBlueprint_path, name)])
        cmd_call('git_clone: ln', ['ln', '-sf', mods, os.path.join(sBlueprint_path, name)])
    else:
        logging.debug("mods empty, performing cmd: ln -sf '%s' '%s'", extra_mods, os.path.join(sAdd_mod_path, name))
        if os.path.lexists(os.path.join(sAdd_mod_path, name)):
            cmd_call('git_clone: rm', ['rm', '-fr', os.path.join(sAdd_mod_path, name)])
        cmd_call('git_clone: ln', ['ln', '-sf', extra_mods, os.path.join(sAdd_mod_path, name)])


def install_bp(bp_element):
    "install_bp(bp_element) Loading the blueprint file and install the required element to make it work on Maestro."
    fYaml, bp_element = load_bp(bp_element)

    if not fYaml or 'blueprint' not in fYaml:
        logging.error('"%s" do not define required "blueprint/" yaml section.', bp_element)
        sys.exit(2)

    BP_DESC = "Undefined blueprint"
    BP_yaml = fYaml['blueprint']
    if 'name' not in BP_yaml:
        logging.error('Your blueprint is not named! It does not have blueprint/name tag.')
        sys.exit(2)
    if 'description' in BP_yaml:
        BP_DESC = BP_yaml['description']
    else:
        logging.warning('"%s" do not define "blueprint/description" data.', bp_element)

    logging.info('Blueprint downloaded: ' + BP_DESC)
    if 'locations' not in BP_yaml:
        logging.error('"%s" do not define required "blueprint/locations" yaml section.', bp_element)
        sys.exit(2)

    BP_BootSeq = []

    if not os.path.exists(BLUEPRINT_REPOS_DIR):
        cmd_call('install_bp', ['mkdir', '-p', BLUEPRINT_REPOS_DIR])
        logging.info('%s has been created.', BLUEPRINT_REPOS_DIR)

    if SOURCES in BP_yaml['locations']:
        dSource = BP_yaml['locations'][SOURCES]
        for vRepo in dSource:
            if 'src-repo' in vRepo:
                if 'git' in vRepo:
                    git_clone(vRepo)
                    if 'install' in vRepo and 'puppet-apply' in vRepo['install']:
                        modules_path = os.path.join(GIT_REPOS_DIR, vRepo['src-repo'], 'puppet', 'modules') + ':' + os.path.join(GIT_REPOS_DIR, 'maestro', 'puppet', 'modules') + ':' + os.path.join('','etc','puppet','modules')
                        manifest_file = os.path.join(GIT_REPOS_DIR, vRepo['src-repo'], 'puppet', 'manifests', vRepo['install']['puppet-apply'] + '.pp')
                        BP_BootSeq.append(['puppet', 'apply', '--debug', '--verbose', '--modulepath=' + modules_path, manifest_file])
                        BP_BootSeq.append(['puppet', 'apply', '--debug', '--verbose', '--modulepath=' + modules_path, manifest_file])
                else:
                    logging.warning("repo-src: Missing 'git' protocol. Currently only supports 'git'.")
            else:
                logging.warning("Supporting Only 'src-repo' repository type in /blueprint/locations/" + SOURCES)
    if not os.path.exists(BLUEPRINT_REF_PATH):
        cmd_call('install_bp', ['mkdir', '-p', BLUEPRINT_REF_PATH])
        logging.info('%s has been created.', BLUEPRINT_REF_PATH)
    try:
        stream = open(os.path.join(BLUEPRINT_REF_PATH, BP_yaml['name'] + '.yaml'), 'w')
        stream.write('# Yaml document automatically generated by \'{0}\'. DO NOT UPDATE IT MANUALLY!\n#\n'.format(sys.argv[0]))
        stream.write('# Source : {0}\n'.format(bp_element))
        stream.write('# Date     : {0:%Y-%m-%d %H:%M:%S}\n#\n---\n'.format(datetime.datetime.now()))
    except IOError as oErr:
        logging.error('Unable to write in \'%s\'.%s But Modules/repos has been already installed. Fix and retry.', oErr.strerror, os.path.join(BLUEPRINT_REF_PATH, BP_yaml['name']))
    else:
        yaml.dump(fYaml, stream)
        stream.close()
        logging.info('Blueprint \'%s\' is saved under \'%s\'', BP_yaml['name'], BLUEPRINT_REF_PATH)

    # If needed, execute a blueprint boot.
    if len(BP_BootSeq):
        for BootSeq in BP_BootSeq:
            if BootSeq[1] == 'puppet':
                logging.info('Starting blueprint install: puppet apply of "%s"', BootSeq[4])
            else:
                logging.info('Starting blueprint install: Running "%s"', " ".join(BootSeq))
            cmd_call('install_bp', BootSeq)


def main(argv):
    """Main function"""

    global TEST_BOX
    global BRANCH
    logging.basicConfig(format='%(asctime)s: %(levelname)s - %(message)s', datefmt='%m/%d/%Y %I:%M:%S %p')
    oLogging = logging.getLogger()
    try:
        opts, args = getopt.getopt(argv, "hI:vd", ["help", "install=", "debug", "verbose", "branch=", 'test-box='])
    except getopt.GetoptError, e:
        print 'Error: ' + e.msg
        help()
        sys.exit(2)

    action = 0
    for opt, arg in opts:
        if opt in ('-h', '--help'):
            help()
            sys.exit()
        elif opt in ('-v', '--verbose'):
            if oLogging.level > 20:
                oLogging.setLevel(oLogging.level - 10)
        elif opt in ('--debug', '-d'):
            print "Setting debug mode"
            oLogging.setLevel(logging.DEBUG)
        elif opt in ('--branch'):
            BRANCH = arg
        elif opt in ('--test-box'):
            logging.debug('test-box: Added \'%s\'.', arg)
            TEST_BOX = arg
        elif opt in ('-I', '--install'):
            ACTION = "install_bp"
            BP = arg
            action = 1
    if action == 0:
        print 'Error: At least --install is required.'
        help()
    else:
        if ACTION == 'install_bp':
            install_bp(BP)
    sys.exit()


if __name__ == "__main__":
    main(sys.argv[1:])
