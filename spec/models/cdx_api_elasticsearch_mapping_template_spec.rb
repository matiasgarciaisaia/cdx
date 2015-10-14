require "bundler/setup"
require "cdx/api/elasticsearch"

RSpec.shared_examples "having institution fields" do
  it " " do
    expect(mapping[:properties]['institution']).to eq({
      "properties" => {
        "uuid" => {
          "type" => "string",
          "index" => "not_analyzed"
        }
      }
    })
  end
end

RSpec.shared_examples "having site fields" do
  it " " do
    expect(mapping[:properties]['site']).to eq({
      "properties" => {
        "uuid" => {
          "type" => "string",
          "index" => "not_analyzed"
        }
      }
    })
  end
end

RSpec.shared_examples "having sample fields" do
  it " " do
    expect(mapping[:properties]['sample']).to eq({
      "properties" => {
        "uuid"=> {
          "type"=> "string",
          "index"=> "not_analyzed"
        },
        "id"=> {
          "type"=> "string",
          "index"=> "not_analyzed"
        },
        "type"=> {
          "type"=> "string",
          "index"=> "not_analyzed"
        },
        "custom_fields" => {
          "type" => "object"
        }
      }
    })
  end
end

RSpec.shared_examples "having test fields" do
  it " " do
    expect(mapping[:properties]['test']).to eq({
      "properties" => {
        "id"=> {
          "type"=>"string",
          "index"=>"not_analyzed"
        },
        "uuid" => {
          "type" => "string",
          "index" => "not_analyzed"
        },
        "start_time"=> {
          "type"=> "date",
          "index"=> "not_analyzed"
        },
        "end_time"=> {
          "type"=> "date",
          "index"=> "not_analyzed"
        },
        "reported_time"=> {
          "type"=> "date",
          "index"=> "not_analyzed"
        },
        "updated_time"=> {
          "type"=> "date",
          "index"=> "not_analyzed"
        },
        "error_code"=> {
          "type"=> "integer",
          "index"=> "not_analyzed"
        },
        "patient_age" => {
          "properties" => {
            "in_millis" => {
              "type" => "long",
              "index" => "not_analyzed"
            },
            "milliseconds" => {
              "type" => "integer",
              "index" => "not_analyzed"
            },
            "seconds" => {
              "type" => "integer",
              "index" => "not_analyzed"
            },
            "minutes" => {
              "type" => "integer",
              "index" => "not_analyzed"
            },
            "hours" => {
              "type" => "integer",
              "index" => "not_analyzed"
            },
            "days" => {
              "type" => "integer",
              "index" => "not_analyzed"
            },
            "months" => {
              "type" => "integer",
              "index" => "not_analyzed"
            },
            "years" => {
              "type" => "integer",
              "index" => "not_analyzed"
            }
          }
        },
        "site_user"=> {
          "type"=> "string",
          "index"=> "not_analyzed"
        },
        "name" => {
          "type" => "string",
          "index" => "not_analyzed"
        },
        "status"=> {
          "type"=> "string",
          "index"=> "not_analyzed"
        },
        "assays" => {
          "type" => "nested",
          "properties" => {
            "name" => {
              "type" => "string",
              "index" => "not_analyzed"
            },
            "condition" => {
              "type" => "string",
              "index" => "not_analyzed"
            },
            "result"=> {
              "type"=> "string",
              "index"=> "not_analyzed"
            }
          }
        },
        "type" => {
          "type" => "string",
          "index" => "not_analyzed"
        },
        "custom_fields" => {
          "type" => "object"
        }
      }
    })
  end
end

RSpec.shared_examples "having device fields" do
  it " " do
    expect(mapping[:properties]['device']).to eq({
      "properties" => {
        "uuid" => {
          "type" => "string",
          "index" => "not_analyzed"
        },
        "model" => {
          "type" => "string",
          "index" => "not_analyzed"
        },
        "serial_number"=> {
          "type"=> "string",
          "index"=> "not_analyzed"
        }
      }
    })
  end
end

RSpec.shared_examples "having location fields" do
  it " " do
    expect(mapping[:properties]['location']).to eq({
      "properties" => {
        "parents" => {
          "type" => "string",
          "index" => "not_analyzed"
        },
        "admin_levels" => {
          "properties" => {}
        }
      }
    })
  end
end

RSpec.shared_examples "having patient fields" do
  it " " do
    expect(mapping[:properties]['patient']).to eq({
      "properties" => {
        "gender" => {
          "type" => "string",
          "index" => "not_analyzed"
        },
        "custom_fields" => {
          "type" => "object"
        }
      }
    })
  end
end

RSpec.shared_examples "having encounter fields" do
  it " " do
    expect(mapping[:properties]['encounter']).to eq({
      "properties"=> {
        "id"=>{"type"=>"string", "index"=>"not_analyzed"},
        "uuid"=>{"type"=>"string", "index"=>"not_analyzed"},
        "start_time"=> {"type"=> "date", "index"=> "not_analyzed"},
        "end_time"=> {"type"=> "date", "index"=> "not_analyzed"},
        "custom_fields"=>{"type"=>"object"}
    }})
  end
end

describe Cdx::Api::Elasticsearch::MappingTemplate do

  let(:template) { Cdx::Api::Elasticsearch::MappingTemplate.new }

  it "generates mappings for all entities" do
    expect(template.template[:mappings].keys).to contain_exactly(:test, :encounter)
  end

  it "builds dynamic templates for locations and custom fields" do
    expect(template.build_dynamic_templates).to eq([
      {
        "admin_levels" => {
          path_match: "*.admin_level_*",
          mapping: {type: :string, index: :not_analyzed}
        }
      },
      {
        "custom_fields" => {
          path_match: "*.custom_fields.*",
          mapping: { enabled: false }
        }
      }
    ])
  end

  describe "encounter mapping" do
    let(:mapping) { template.template[:mappings][:encounter] }

    it_should_behave_like 'having encounter fields'
    it_should_behave_like 'having patient fields'
    it_should_behave_like 'having institution fields'
  end

  describe "test mapping" do
    let(:mapping) { template.template[:mappings][:test] }

    it_should_behave_like 'having test fields'
    it_should_behave_like 'having sample fields'
    it_should_behave_like 'having device fields'
    it_should_behave_like 'having site fields'
    it_should_behave_like 'having location fields'
    it_should_behave_like 'having encounter fields'
    it_should_behave_like 'having patient fields'
    it_should_behave_like 'having institution fields'
  end

end
