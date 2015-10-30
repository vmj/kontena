require 'docker'

module Kontena
  module ServicePods
    class Starter

      attr_reader :service_name

      # @param [String] service_name
      def initialize(service_name)
        @service_name = service_name
      end

      def perform
        service_container = get_container(self.service_name)
        unless service_container.running?
          service_container.restart
        end
      end

      # @return [Celluloid::Future]
      def perform_async
        Celluloid::Future.new { self.perform }
      end

      private

      # @return [Docker::Container, NilClass]
      def get_container(name)
        Docker::Container.get(name) rescue nil
      end
    end
  end
end
