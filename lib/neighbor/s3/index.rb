module Neighbor
  module S3
    class Index
      def initialize(name, bucket:, dimensions:, distance:, id_type: "string", non_filterable: nil)
        @name = name
        @bucket = bucket
        @dimensions = dimensions.to_i

        @distance_metric =
          case distance.to_s
          when "euclidean"
            "euclidean"
          when "cosine"
            "cosine"
          else
            raise ArgumentError, "invalid distance"
          end

        @int_ids =
          case id_type.to_s
          when "string"
            false
          when "integer"
            true
          else
            raise ArgumentError, "invalid id_type"
          end

        @non_filterable = non_filterable.to_a
      end

      def self.create(*args, **options)
        index = new(*args, **options)
        index.create
        index
      end

      def create
        options = {
          vector_bucket_name: @bucket,
          index_name: @name,
          data_type: "float32",
          dimension: @dimensions,
          distance_metric: @distance_metric
        }
        if @non_filterable.any?
          options[:metadata_configuration] = {
            non_filterable_metadata_keys: @non_filterable
          }
        end
        client.create_index(options)
        nil
      end

      def exists?
        client.get_index({
          vector_bucket_name: @bucket,
          index_name: @name
        })
        true
      rescue Aws::S3Vectors::Errors::NotFoundException
        false
      end

      def info
        client.get_index({
          vector_bucket_name: @bucket,
          index_name: @name
        }).index.to_h
      end

      def add(id, vector, metadata: nil)
        add_all([{id: id, vector: vector, metadata: metadata}])
      end

      def add_all(items)
        # perform checks first to reduce chance of non-atomic updates
        vectors =
          items.map do |item|
            vector = item.fetch(:vector).to_a
            check_dimensions(vector)

            {
              key: item_id(item.fetch(:id)).to_s,
              data: {float32: vector},
              metadata: item[:metadata]
            }
          end

        vectors.each_slice(500) do |batch|
          client.put_vectors({
            vector_bucket_name: @bucket,
            index_name: @name,
            vectors: batch
          })
        end
        nil
      end

      def member?(id)
        id = item_id(id)

        client.get_vectors({
          vector_bucket_name: @bucket,
          index_name: @name,
          keys: [id.to_s],
          return_data: false,
          return_metadata: false
        }).vectors.any?
      end
      alias_method :include?, :member?

      def remove(id)
        remove_all([id])
      end

      def remove_all(ids)
        ids = ids.to_a.map { |id| item_id(id) }

        ids.each_slice(500) do |batch|
          client.delete_vectors({
            vector_bucket_name: @bucket,
            index_name: @name,
            keys: batch.map(&:to_s)
          })
        end
        nil
      end

      def find(id, with_metadata: true)
        id = item_id(id)

        v =
          client.get_vectors({
            vector_bucket_name: @bucket,
            index_name: @name,
            keys: [id.to_s],
            return_data: true,
            return_metadata: with_metadata
          }).vectors.first

        if v
          item = {
            id: item_id(v.key),
            vector: v.data.float32
          }
          item[:metadata] = v.metadata if with_metadata
          item
        end
      end

      def find_in_batches(batch_size: 1000, with_metadata: true)
        options = {
          vector_bucket_name: @bucket,
          index_name: @name,
          max_results: batch_size,
          return_data: true,
          return_metadata: with_metadata
        }

        begin
          resp = client.list_vectors(options)
          batch =
            resp.vectors.map do |v|
              item = {
                id: item_id(v.key),
                vector: v.data.float32
              }
              item[:metadata] = v.metadata if with_metadata
              item
            end
          yield batch
          options[:next_token] = resp.next_token
        end while resp.next_token
      end

      def search(vector, count: 5, with_metadata: false, filter: nil)
        check_dimensions(vector)

        client.query_vectors({
          vector_bucket_name: @bucket,
          index_name: @name,
          top_k: count,
          query_vector: {
            float32: vector,
          },
          filter: filter,
          return_metadata: with_metadata,
          return_distance: true
        }).vectors.map do |v|
          item = {
            id: item_id(v.key),
            distance: @distance_metric == "euclidean" ? Math.sqrt(v.distance) : v.distance
          }
          item[:metadata] = v.metadata if with_metadata
          item
        end
      end

      def search_id(id, count: 5, with_metadata: false, filter: nil)
        id = item_id(id)

        item = find(id)
        unless item
          raise Error, "Could not find item #{id}"
        end

        result = search(item[:vector], count: count + 1, with_metadata:, filter:)
        result.reject { |v| v[:id] == id }.first(count)
      end

      def drop
        client.delete_index({
          vector_bucket_name: @bucket,
          index_name: @name
        })
        nil
      end

      private

      def check_dimensions(vector)
        if vector.size != @dimensions
          raise ArgumentError, "expected #{@dimensions} dimensions"
        end
      end

      def item_id(id)
        @int_ids ? Integer(id) : id.to_s
      end

      def client
        S3.client
      end
    end
  end
end
