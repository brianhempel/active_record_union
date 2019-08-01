require 'active_record_union/version'
require 'active_record'
require 'active_record_union/active_record/relation/utils'
require 'active_record_union/active_record/relation/union'
require 'active_record_union/active_record/relation/intersect'

module ActiveRecord
  class Relation
    include Utils
    include Union
    include Intersect
  end
end
