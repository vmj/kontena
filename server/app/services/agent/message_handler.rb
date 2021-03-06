module Agent
  class MessageHandler

    ##
    # @param [Queue] queue
    def initialize(queue)
      @queue = queue
    end

    def run
      Thread.new {
        loop do
          begin
            message = @queue.pop
            self.handle_message(message)
          rescue => exc
            puts "#{exc.class.name}: #{exc.message}"
            puts exc.backtrace.join("\n") if exc.backtrace
          end
        end
      }
    end

    ##
    # @param [Hash] message
    def handle_message(message)
      grid = Grid.find_by(id: message['grid_id'])
      return if grid.nil?

      data = message['data']
      case data['event']
        when 'node:info'
          self.on_node_info(grid, data['data'])
        when 'container:info'
          self.on_container_info(grid, data['data'])
        when 'container:event'
          self.on_container_event(grid, data['data'])
        when 'container:log'
          self.on_container_log(grid, message['node_id'], data['data'])
        when 'container:stats'
          self.on_container_stat(grid, data['data'])
        else
          puts "unknown event: #{message}"
      end
    end

    ##
    # @param [Grid] grid
    # @param [Hash] data
    def on_node_info(grid, data)
      node = grid.host_nodes.find_by(node_id: data['ID'])
      if !node
        node = grid.host_nodes.build
      end
      node.attributes_from_docker(data)
      node.save!
    end

    ##
    # @param [Grid] grid
    # @param [Hash] data
    def on_container_info(grid, data)
      info = data['container']
      labels = info['Config']['Labels'] || {}
      container_id = info['Id']
      container = grid.containers.unscoped.find_by(container_id: container_id)
      if container
        container.attributes_from_docker(info)
        container.updated_at = Time.now.utc
        container.save
      elsif !labels['io.kontena.container.id'].nil?
        container = grid.containers.unscoped.find_by(id: labels['io.kontena.container.id'])
        unless container
          node = grid.host_nodes.find_by(node_id: data['node'])
          service = grid.grid_services.find_by(id: labels['io.kontena.service.id'])
          container = grid.containers.build(
            id: BSON::ObjectId.from_string(labels['io.kontena.container.id']),
            container_id: container_id,
            name: labels['io.kontena.container.name'],
            container_type: labels['io.kontena.container.type'] || 'container',
            grid_service: service,
            host_node: node
          )
        end
        container.attributes_from_docker(info)
        container.save
      else
        node = grid.host_nodes.find_by(node_id: data['node'])
        container = grid.containers.build(
          container_id: container_id,
          name: info['Name'].split("/")[1],
          container_type: 'container',
          host_node: node
        )
        container.attributes_from_docker(info)
        container.save
      end
    rescue Moped::Errors::OperationFailure
    end

    ##
    # @param [Grid] grid
    # @param [Hash] data
    def on_container_event(grid, data)
      container = grid.containers.unscoped.find_by(container_id: data['id'])
      if container
        if data['status'] == 'destroy'
          container.mark_for_delete
        end
      end
    end

    ##
    # @param [Grid] grid
    # @param [String] node_id
    # @param [Hash] data
    def on_container_log(grid, node_id, data)
      container = grid.containers.find_by(container_id: data['id'])
      if container
        if data['time']
          created_at = Time.parse(data['time'])
        else
          created_at = Time.now.utc
        end
        ContainerLog.with(safe: false).create(
            grid: grid,
            host_node_id: node_id,
            grid_service: container.grid_service,
            container: container,
            created_at: created_at,
            name: container.name,
            type: data['type'],
            data: data['data']
        )
      end
    end

    ##
    # @param [Grid] grid
    # @param [Hash] data
    def on_container_stat(grid, data)
      data = fixnums_to_float(data)
      container = grid.containers.find_by(container_id: data['id'])
      if container
        ContainerStat.with(safe: false).create(
            grid: grid,
            grid_service: container.grid_service,
            container: container,
            spec: data['spec'],
            cpu: data['cpu'],
            memory: data['memory'],
            filesystem: data['filesystem'],
            diskio: data['diskio'],
            network: data['network']
        )
      end
    end

    ##
    # @param [Hash,Array]
    # @return [Hash,Array]
    def fixnums_to_float(h)
      i = 0
      h.each do |k, v|
        # If v is nil, an array is being iterated and the value is k.
        # If v is not nil, a hash is being iterated and the value is v.
        #
        value = v || k

        if value.is_a?(Hash) || value.is_a?(Array)
          fixnums_to_float(value)
        else
          if !v.nil? && value.is_a?(Bignum)
            h[k] = value.to_f
          elsif v.nil? && value.is_a?(Bignum)
            h[i] = value.to_f
          end
        end
        i += 1
      end
    end
  end
end
