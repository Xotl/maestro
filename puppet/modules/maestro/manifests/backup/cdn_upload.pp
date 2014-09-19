# == Class: ::maestro::backup::cdn_upload
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

# This Puppet manifests uploads the backup files from maestro to object storage

class maestro::backup::cdn_upload (
)
{
  include maestro::backup::params
  # master_bkp.sh runs at 00:20, we are leaving 4 hours to complete
  schedule { 'backup-schedule':
    period => daily,
    range  => '4:20 - 6:20',
    repeat => 1,
  }
  exec {'tar-mnt-backups':
    cwd      => $maestro::backup::params::backup_fullpath,
    command  => "/bin/tar cvf ${maestro::backup::params::maestro_tar_file} ${maestro::backup::params::backup_fullpath}/*",
    onlyif   => "/usr/bin/test -e ${maestro::backup::params::backup_fullpath}"
  }
  pinascdn {'pinas-upload':
    ensure      => present,
    file_name   => $maestro::backup::params::maestro_tar_file,
    remote_dir  => $::domain,
    local_dir   => $maestro::backup::params::backup_fullpath,
    schedule    => 'backup-schedule',
    subscribe   => Exec['tar-mnt-backups'],
  }
}
