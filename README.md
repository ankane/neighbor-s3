# Neighbor S3

Nearest neighbor search for Ruby and S3 Vectors

## Installation

Add this line to your application’s Gemfile:

```ruby
gem "neighbor-s3"
```

Create a [vector bucket](https://console.aws.amazon.com/s3/vector-buckets) and set your AWS credentials in your environment:

```sh
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
```

## Getting Started

Create an index

```ruby
index = Neighbor::S3::Index.new("items", bucket: "my-bucket", dimensions: 3, distance: "cosine")
index.create
```

Add vectors

```ruby
index.add(1, [1, 1, 1])
index.add(2, [2, 2, 2])
index.add(3, [1, 1, 2])
```

Search for nearest neighbors to a vector

```ruby
index.search([1, 1, 1], count: 5)
```

Search for nearest neighbors to a vector in the index

```ruby
index.search_id(1, count: 5)
```

IDs are treated as strings by default, but can also be treated as integers

```ruby
Neighbor::S3::Index.new("items", id_type: "integer", ...)
```

## Operations

Add or update a vector

```ruby
index.add(id, vector)
```

Add or update multiple vectors

```ruby
index.add_all([{id: 1, vector: [1, 2, 3]}, {id: 2, vector: [4, 5, 6]}])
```

Get a vector

```ruby
index.find(id)
```

Get all vectors

```ruby
index.find_in_batches do |batch|
  # ...
end
```

Remove a vector

```ruby
index.remove(id)
```

Remove multiple vectors

```ruby
index.remove_all(ids)
```

## Metadata

Add a vector with metadata

```ruby
index.add(id, vector, metadata: {category: "A"})
```

Add multiple vectors with metadata

```ruby
index.add_all([
  {id: 1, vector: [1, 2, 3], metadata: {category: "A"}},
  {id: 2, vector: [4, 5, 6], metadata: {category: "B"}}
])
```

Get metadata with search results

```ruby
index.search(vector, with_metadata: true)
```

Filter by metadata

```ruby
index.search(vector, filter: {category: "A"})
```

Supports [these operators](https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-vectors-metadata-filtering.html#s3-vectors-metadata-filtering-filterable)

Specify non-filterable metadata on index creation

```ruby
Neighbor::S3::Index.new(name, non_filterable: ["category"], ...)
```

## Example

You can use Neighbor S3 for online item-based recommendations with [Disco](https://github.com/ankane/disco). We’ll use MovieLens data for this example.

Create an index

```ruby
index = Neighbor::S3::Index.new("movies", bucket: "my-bucket", dimensions: 20, distance: "cosine")
```

Fit the recommender

```ruby
data = Disco.load_movielens
recommender = Disco::Recommender.new(factors: 20)
recommender.fit(data)
```

Store the item factors

```ruby
index.add_all(recommender.item_ids.map { |v| {id: v, vector: recommender.item_factors(v)} })
```

And get similar movies

```ruby
index.search_id("Star Wars (1977)").map { |v| v[:id] }
```

See the [complete code](examples/disco_item_recs.rb)

## Reference

Get index info

```ruby
index.info
```

Check if an index exists

```ruby
index.exists?
```

Drop an index

```ruby
index.drop
```

## History

View the [changelog](https://github.com/ankane/neighbor-s3/blob/master/CHANGELOG.md)

## Contributing

Everyone is encouraged to help improve this project. Here are a few ways you can help:

- [Report bugs](https://github.com/ankane/neighbor-s3/issues)
- Fix bugs and [submit pull requests](https://github.com/ankane/neighbor-s3/pulls)
- Write, clarify, or fix documentation
- Suggest or add new features

To get started with development:

```sh
git clone https://github.com/ankane/neighbor-s3.git
cd neighbor-s3
bundle install
bundle exec rake test
```
