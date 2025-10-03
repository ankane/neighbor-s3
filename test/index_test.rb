require_relative "test_helper"

class IndexTest < Minitest::Test
  def setup
    super
    index = Neighbor::S3::Index.new("items", bucket: bucket, dimensions: 3, distance: "euclidean")
    index.drop if index.exists?
  end

  def test_create
    index = Neighbor::S3::Index.new("items", bucket: bucket, dimensions: 3, distance: "euclidean")
    assert_nil index.create
  end

  def test_create_exists
    index = create_index

    error = assert_raises(Aws::S3Vectors::Errors::ConflictException) do
      index.create
    end
    assert_equal "An index with the specified name already exists", error.message
  end

  def test_exists
    index = Neighbor::S3::Index.new("items", bucket: bucket, dimensions: 3, distance: "euclidean")
    assert_equal false, index.exists?
    index.create
    assert_equal true, index.exists?
  end

  def test_info
    index = create_index
    info = index.info
    assert_equal "items", info[:index_name]
    assert_equal "float32", info[:data_type]
    assert_equal 3, info[:dimension]
    assert_equal "cosine", info[:distance_metric]
  end

  def test_info_missing
    index = Neighbor::S3::Index.new("items", bucket: bucket, dimensions: 3, distance: "euclidean")
    error = assert_raises(Aws::S3Vectors::Errors::NotFoundException) do
      index.info
    end
    assert_equal "The specified index could not be found", error.message
  end

  def test_add
    index = create_index
    assert_nil index.add(1, [1, 1, 1])
    assert_nil index.add(1, [2, 2, 2])
    assert_equal [2, 2, 2], index.find(1)[:vector]
  end

  def test_add_metadata
    index = create_index
    assert_nil index.add(1, [1, 1, 1], metadata: {category: "A"})
    assert_equal ({"category" => "A"}), index.find(1)[:metadata]

    assert_nil index.add(1, [2, 2, 2])
    assert_empty index.find(1)[:metadata]
  end

  def test_add_different_dimensions
    index = create_index
    error = assert_raises(ArgumentError) do
      index.add(4, [1, 2])
    end
    assert_equal "expected 3 dimensions", error.message
  end

  def test_add_before_create
    index = Neighbor::S3::Index.new("items", bucket: bucket, dimensions: 3, distance: "euclidean", id_type: "integer")
    error = assert_raises(Aws::S3Vectors::Errors::NotFoundException) do
      index.add(1, [1, 1, 1])
    end
    assert_equal "The specified index could not be found", error.message
  end

  def test_add_all
    index = create_index
    assert_nil index.add_all([{id: 1, vector: [1, 1, 1]}, {id: 2, vector: [2, 2, 2]}])
    assert_nil index.add_all([{id: 1, vector: [1, 1, 1]}, {id: 3, vector: [1, 1, 2]}])
  end

  def test_add_all_different_dimensions
    index = create_index
    error = assert_raises(ArgumentError) do
      index.add_all([{id: 1, vector: [1, 1, 1]}, {id: 4, vector: [1, 2]}])
    end
    assert_equal "expected 3 dimensions", error.message
  end

  def test_add_all_missing_key
    index = create_index
    error = assert_raises(KeyError) do
      index.add_all([{id: 1}])
    end
    assert_equal "key not found: :vector", error.message
  end

  def test_member
    index = create_index
    add_items(index)
    assert_equal true, index.member?(2)
    assert_equal false, index.member?(4)
  end

  def test_include
    index = create_index
    add_items(index)
    assert_equal true, index.include?(2)
    assert_equal false, index.include?(4)
  end

  def test_remove
    index = create_index(distance: "euclidean", id_type: "integer")
    add_items(index)
    assert_nil index.remove(2)
    assert_nil index.remove(4)
    assert_equal [1, 3], index.search([1, 1, 1]).map { |v| v[:id] }
  end

  def test_remove_all
    index = create_index(distance: "euclidean", id_type: "integer")
    add_items(index)
    assert_nil index.remove_all([2, 4])
    assert_equal [1, 3], index.search([1, 1, 1]).map { |v| v[:id] }
  end

  def test_find
    index = create_index
    add_items(index)
    assert_elements_in_delta [1, 1, 1], index.find(1)[:vector]
    assert_elements_in_delta [2, 2, 2], index.find(2)[:vector]
    assert_elements_in_delta [1, 1, 2], index.find(3)[:vector]
    assert_nil index.find(4)
  end

  def test_find_metadata
    index = create_index
    index.add(1, [1, 1, 1], metadata: {category: "A"})
    index.add(2, [-1, -1, -1], metadata: {category: "B"})
    index.add(3, [1, 1, 0])

    assert_equal ({"category" => "A"}), index.find(1)[:metadata]
    assert_equal ({"category" => "B"}), index.find(2)[:metadata]
    assert_empty index.find(3)[:metadata]
    assert_nil index.find(4)
  end

  def test_find_in_batches
    index = create_index
    add_items(index)
    batches = []
    index.find_in_batches(batch_size: 2) do |batch|
      batches << batch
    end
    assert_equal 2, batches.size
  end

  def test_find_in_batches_batch_size
    index = create_index
    error = assert_raises(Aws::S3Vectors::Errors::ValidationException) do
      index.find_in_batches(batch_size: 1001)
    end
    assert_match "Member must be between 1 and 1000, inclusive", error.message
  end

  def test_search_euclidean
    index = create_index(distance: "euclidean", id_type: "integer")
    add_items(index)
    result = index.search([1, 1, 1])
    assert_equal [1, 3, 2], result.map { |v| v[:id] }
    assert_elements_in_delta [0, 1, 1.7320507764816284], result.map { |v| v[:distance] }
  end

  def test_search_cosine
    index = create_index(distance: "cosine", id_type: "integer")
    index.add(1, [1, 1, 1])
    index.add(2, [-1, -1, -1])
    index.add(3, [1, 1, 2])
    result = index.search([1, 1, 1])
    assert_equal [1, 3, 2], result.map { |v| v[:id] }
    assert_elements_in_delta [0, 0.05719095841050148, 2], result.map { |v| v[:distance] }
  end

  def test_search_with_metadata
    index = create_index
    index.add(1, [1, 1, 1], metadata: {category: "A", quantity: 2})
    index.add(2, [-1, -1, -1], metadata: {category: "B", quantity: 4})
    index.add(3, [1, 1, 0])

    result = index.search([1, 1, 1], with_metadata: true)
    assert_equal ({"category" => "A", "quantity" => 2}), result[0][:metadata]
    assert_empty result[1][:metadata]
    assert_equal ({"category" => "B", "quantity" => 4}), result[2][:metadata]
  end

  def test_search_filter
    index = create_index(distance: "cosine", id_type: "integer")
    index.add(1, [1, 1, 1], metadata: {category: "A", quantity: 2})
    index.add(2, [-1, -1, -1], metadata: {category: "B", quantity: 4})
    index.add(3, [1, 1, 0])

    result = index.search([1, 1, 1], filter: {category: "B"})
    assert_equal [2], result.map { |v| v[:id] }

    result = index.search([1, 1, 1], filter: {quantity: {"$gt" => 2}})
    assert_equal [2], result.map { |v| v[:id] }

    result = index.search([1, 1, 1], filter: {quantity: {"$exists" => true}})
    assert_equal [1, 2], result.map { |v| v[:id] }
  end

  def test_search_non_filterable
    index = create_index(distance: "cosine", id_type: "integer", non_filterable: ["category"])
    index.add(1, [1, 1, 1], metadata: {category: "A"})

    error = assert_raises(Aws::S3Vectors::Errors::ValidationException) do
      index.search([1, 1, 1], filter: {category: "A"})
    end
    assert_equal "Invalid use of non-filterable metadata in filter", error.message
  end

  def test_search_different_dimensions
    index = create_index
    error = assert_raises(ArgumentError) do
      index.search([1, 2])
    end
    assert_equal "expected 3 dimensions", error.message
  end

  def test_search_id_euclidean
    index = create_index(distance: "euclidean", id_type: "integer")
    add_items(index)
    result = index.search_id(1)
    assert_equal [3, 2], result.map { |v| v[:id] }
    assert_elements_in_delta [1, 1.7320507764816284], result.map { |v| v[:distance] }
  end

  def test_search_id_cosine
    index = create_index(distance: "cosine", id_type: "integer")
    add_items(index)
    result = index.search_id(1)
    assert_equal [2, 3], result.map { |v| v[:id] }
    assert_elements_in_delta [0, 0.05719095841050148], result.map { |v| v[:distance] }
  end

  def test_search_id_with_metadata
    index = create_index
    index.add(1, [1, 1, 1], metadata: {category: "A", quantity: 2})
    index.add(2, [-1, -1, -1], metadata: {category: "B", quantity: 4})
    index.add(3, [1, 1, 0])

    result = index.search_id(1, with_metadata: true)
    assert_empty result[0][:metadata]
    assert_equal ({"category" => "B", "quantity" => 4}), result[1][:metadata]
  end

  def test_search_id_filter
    index = create_index(distance: "cosine", id_type: "integer")
    index.add(1, [1, 1, 1], metadata: {category: "A", quantity: 2})
    index.add(2, [-1, -1, -1], metadata: {category: "B", quantity: 4})
    index.add(3, [1, 1, 0])

    result = index.search_id(1, filter: {category: "B"})
    assert_equal [2], result.map { |v| v[:id] }
  end

  def test_search_id_missing
    index = create_index
    error = assert_raises(Neighbor::S3::Error) do
      index.search_id(4)
    end
    assert_equal "Could not find item 4", error.message
  end

  def test_drop
    index = create_index
    assert_equal true, index.exists?
    assert_nil index.drop
    assert_equal false, index.exists?
    assert_nil index.drop
  end

  def test_id_type_integer
    index = create_index(distance: "euclidean", id_type: "integer")
    index.add(1, [1, 1, 1])
    index.add("2", [-1, -1, -1])
    error = assert_raises(ArgumentError) do
      index.add("3a", [1, 1, 0])
    end
    assert_match "invalid value for Integer()", error.message
    assert_equal [2], index.search_id(1).map { |v| v[:id] }
    assert_equal [1, 2], index.search([1, 1, 1]).map { |v| v[:id] }
  end

  def test_id_type_string
    index = create_index(distance: "euclidean", id_type: "string")
    index.add(1, [1, 1, 1])
    index.add("2", [-1, -1, -1])
    assert_equal ["2"], index.search_id(1).map { |v| v[:id] }
    assert_equal ["1", "2"], index.search([1, 1, 1]).map { |v| v[:id] }
  end

  private

  def create_index(**options)
    options[:distance] ||= ["euclidean", "cosine"].sample
    Neighbor::S3::Index.create("items", bucket: bucket, dimensions: 3, **options)
  end

  def add_items(index)
    items = [
      {id: 1, vector: [1, 1, 1]},
      {id: 2, vector: [2, 2, 2]},
      {id: 3, vector: [1, 1, 2]}
    ]
    index.add_all(items)
  end
end
