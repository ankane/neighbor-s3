require "disco"
require "neighbor-s3"

index = Neighbor::S3::Index.new("movies", bucket: "my-bucket", dimensions: 20, distance: "cosine")
index.drop if index.exists?
index.create

data = Disco.load_movielens
recommender = Disco::Recommender.new(factors: 20)
recommender.fit(data)

index.add_all(recommender.item_ids.map { |v| {id: v, vector: recommender.item_factors(v)} })

pp index.search_id("Star Wars (1977)").map { |v| v[:id] }
