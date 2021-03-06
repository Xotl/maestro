# == jimador::maestro_blueprint
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
# parse the meta.js and figure out the instance id 
require 'json'
Facter.add("maestro_blueprint") do
 confine :kernel => "Linux"
 setcode do
     #this is the location of the config file to use in the ERO UI, this file should be stored in the puppet master server.
     metafspec =  Facter.value('meta_location')
     @meta_data = JSON.parse(File.read(metafspec))
     ero_blueprint   = @meta_data['blueprint']
     Facter::Util::Resolution.exec("echo #{ero_blueprint}")
 end
end
