/**
    (c) Copyright 2014 Hewlett-Packard Development Company, L.P.

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

        http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.
*/
/**
 * ProjectController
 *
 * @module      :: Controller
 * @description :: A set of functions called `actions`.
 *
 *                 Actions contain code telling Sails how to respond to a certain type of request.
 *                 (i.e. do stuff, then send some JSON, show an HTML page, or redirect to another URL)
 *
 *                 You can configure the blueprint URLs which trigger these actions (`config/controllers.js`)
 *                 and/or override them with custom routes (`config/routes.js`)
 *
 *                 NOTE: The code you write here supports both HTTP and Socket.io automatically.
 *
 * @docs        :: http://sailsjs.org/#!documentation/controllers
 */

/**
 *
 * @type {{create: create, _config: {}}}
 */
var blueprint_utils = require('blueprint/blueprint');
var project_utils = require('projects/projects');
var configJson = require('config-json-helper');
var msg = require('msg-util').Message;
var queue_util = require('queue-util').Queue;


module.exports = {
  /**
   * Action blueprints:
   *    `/project/create`
   */
  create: function (req, res) {
    if(req.session.project_visibility){
      // Message to be published in Rabbitmq
      var options = {
        ctx: 'project.create.' + req.body.project_name.replace(' ',''),
        name: req.body.project_name,
        desc: req.body.project_name,
        id: configJson.get('site:id'),
        user: req.session.email,
        role: 'admins',
        debug: true,
        log: {
          enable: true,
          level: 'info',
          target: ''
          },
        origin: 'maestro',
        time_stamp: new Date().toISOString()
      };

      if (msg.isValid(options)){
        var rabbitmqConnectionOptions = sails.config.env.rabbitmq.connection;
        var rabbitmqImplOptions = { defaultExchangeName: sails.config.env.rabbitmq.exchange_name, reconnect: false };
        var exchangeName = sails.config.env.rabbitmq.exchange_name;
        var exchangeOptions = sails.config.env.rabbitmq.exchange_options;
        var payload = msg.getJSON(options);
        var routingKey = 'project.create.' + req.body.project_name.replace(' ','');

        queue_util.publish(rabbitmqConnectionOptions, rabbitmqImplOptions, exchangeName, exchangeOptions, payload, routingKey, function(error) {
          if (error){
            console.error(error.message ? error.message : error);
            res.json(error.message ? error.message : error);
          }else{
            res.json(null);
          }
        });
      }else {
        console.error('ProjectController error, msg is not valid: ' + JSON.stringify(options));
        res.json(new Error('Project name is not valid!').message);
      }
    }else{
      res.view('403', { layout: null });
    }
  },
  index: function(req, res){
    if(req.session.project_visibility){
      project_utils.getProjectsList(function (error, stdout, stderr) {
        if (error){
          res.view('403', { layout: null });
        }else{
          res.view({ layout: null, projects_list: stdout, gerritIp: project_utils.getGerritIp() });
        }
      });
    }else{
      res.view('403', { layout: null });
    }
  },
  new: function(req, res){
    if(req.session.project_visibility){
      blueprint_utils.get_blueprint_id(function(err){
        console.error('Unable to get the instance_id of the kit: '+err.message);
        res.view('500', { layout: null, errors: [ 'Unable to get the instance_id of the kit: '+err.message ]});
      }, function(result){
          if(result === undefined){
            res.view('500', { layout: null, errors: [ 'Unable to get the instance_id of the kit: '+err.message ]});
          }else{

            try{
              result = JSON.parse(result);
            }catch(e){
              result = new Error('Unable to parse malformed JSON');
            }

            if(result instanceof Error){
              sails.log.debug('Unable to get the instance_id of the kit: '+result.message);
              res.view('500', { layout: null, errors: [ 'Unable to get the instance_id of the kit: '+result.message ]});
            }else{
              blueprint_utils.get_blueprint_section(result.id, 'tools', function(err){
                console.error('Unable to retrieve the list of tools:'+err.message);
                callback(err, tools);
              }, function(res_tools){
                tools = JSON.parse(res_tools);
                tools.forEach(function(tool) {
                  if(tool.name=='gerrit'){
                    res.view({ layout: null, gerrit_url: tool.tool_url });
                  }
                });
              })
            }
          }
      });
    }else{
      res.view('403', { layout: null });
    }
  },
  /**
   * Overrides for the settings in `config/controllers.js`
   * (specific to ProjectController)
   */
  _config: {}


};