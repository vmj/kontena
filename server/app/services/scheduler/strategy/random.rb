module Scheduler
  module Strategy
    class Random

      ##
      # @param [GridService] grid_service
      # @param [Integer] instance_number
      # @param [Array<HostNode>] nodes
      def find_node(grid_service, container_name, nodes)
        if grid_service.stateless?
          nodes.sample
        else
          container_name = "#{grid_service.name}-#{instance_number}"
          prev_container = grid_service.containers.find_by(name: container_name)
          if prev_container
            prev_container.host_node
          else
            nodes.sample
          end
        end
      end
    end
  end
end
