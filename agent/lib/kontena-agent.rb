require 'docker'
require 'faye/websocket'
require 'eventmachine'
require 'thread'
require 'celluloid'
require 'active_support/core_ext/time'
require 'active_support/core_ext/module/delegation'

Celluloid.logger.level = Logger::ERROR

Excon.defaults[:ssl_verify_peer] = false # if ENV['DISABLE_SSL_VERIFY_PEER']

require_relative 'docker/container'
require_relative 'kontena/pubsub'
require_relative 'kontena/weave_attacher'
require_relative 'kontena/node_info_worker'
require_relative 'kontena/container_info_worker'
require_relative 'kontena/event_worker'
require_relative 'kontena/log_worker'
require_relative 'kontena/queue_worker'
require_relative 'kontena/stats_worker'
require_relative 'kontena/websocket_client'
require_relative 'kontena/etcd_launcher'
require_relative 'kontena/cadvisor_launcher'
require_relative 'kontena/load_balancer_registrator'
require_relative 'kontena/agent'
