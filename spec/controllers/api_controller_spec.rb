require 'spec_helper'

describe ApiController do
  let(:device) {Device.make}
  let(:institution) {device.institution}
  let(:data) {Oj.dump results: [result: :positive]}

  def all_elasticsearch_events
    client = Elasticsearch::Client.new log: true
    client.indices.refresh index: institution.elasticsearch_index_name
    client.search(index: institution.elasticsearch_index_name)["hits"]["hits"]
  end

  def get_updates(options, body="")
    client = Elasticsearch::Client.new log: true
    client.indices.refresh index: institution.elasticsearch_index_name
    response = get :events, body, options
    response.status.should eq(200)
    Oj.load response.body
  end

  context "Creation" do
    it "should create event in the database" do
      response = post :create, data, device_uuid: device.secret_key
      response.status.should eq(200)

      event = Event.first
      event.device_id.should eq(device.id)
      event.raw_data.should_not eq(data)
      event.decrypt.raw_data.should eq(data)
    end

    it "should create event in elasticsearch" do
      post :create, data, device_uuid: device.secret_key

      event = all_elasticsearch_events.first["_source"]
      event["results"].first["result"].should eq("positive")
      event["created_at"].should_not eq(nil)
      event["device_uuid"].should eq(device.secret_key)
      Event.first.uuid.should eq(event["uuid"])
    end

    it "should store institution_id in elasticsearch" do
      post :create, data, device_uuid: device.secret_key

      event = all_elasticsearch_events.first["_source"]
      event["institution_id"].should eq(device.institution_id)
    end

    it "should override event if event_id is the same" do
      post :create, Oj.dump(event_id: "1234", age: 20), device_uuid: device.secret_key

      event = Event.first
      event.event_id.should eq("1234")

      post :create, Oj.dump(event_id: "1234", age: 30, patient_id: 20), device_uuid: device.secret_key

      Event.count.should eq(1)
      event = Event.first.decrypt
      raw_data = Oj.load event.raw_data
      raw_data["age"].should eq(30)
      event.sensitive_data[:patient_id].should eq(20)

      events = all_elasticsearch_events
      events.size.should eq(1)
      event = events.first
      event["_source"]["event_id"].should eq("1234")
      event["_id"].should eq("#{device.secret_key}_1234")
      event["_source"]["age"].should eq(30)

      post :create, Oj.dump(event_id: "1234", age: 20, patient_id: 22), device_uuid: Device.make(institution: institution).secret_key

      Event.count.should eq(2)
      events = all_elasticsearch_events
      events.size.should eq(2)
    end
  end

  context "Manifest" do
    it "shouldn't store sensitive data in elasticsearch" do
      post :create, Oj.dump(results:[result: :positive], patient_id: 1234), device_uuid: device.secret_key

      event = all_elasticsearch_events.first["_source"]
      event["results"].first["result"].should eq("positive")
      event["created_at"].should_not eq(nil)
      event["patient_id"].should eq(nil)
    end

    it "applies an existing manifest" do
      Manifest.create definition: %{{
        "metadata" : {
          "device_models" : ["#{device.device_model.name}"],
          "version" : 1
        },
        "field_mapping" : [{
            "target_field" : "assay_name",
            "selector" : "assay.name",
            "type" : "core"
          }]
      }}
      post :create, Oj.dump(assay: {name: "GX4002"}, patient_id: 1234), device_uuid: device.secret_key

      event = all_elasticsearch_events.first["_source"]
      event["assay_name"].should eq("GX4002")
      event["created_at"].should_not eq(nil)
      event["patient_id"].should be(nil)
    end

    it "stores pii according to manifest" do
      Manifest.create definition: %{{
        "metadata" : {
          "device_models" : ["#{device.device_model.name}"],
          "version" : 1
        },
        "field_mapping" : [
          {
            "target_field": "assay_name",
            "selector" : "assay.name",
            "type" : "core"
          },
          {
            "target_field": "foo",
            "selector" : "patient_id",
            "type" : "custom",
            "pii": true
          }
        ]
      }}

      post :create, Oj.dump(assay: {name: "GX4002"}, patient_id: 1234), device_uuid: device.secret_key

      event = all_elasticsearch_events.first["_source"]
      event["assay_name"].should eq("GX4002")
      event["patient_id"].should eq(nil)
      event["foo"].should be(nil)

      event = Event.first
      raw_data = event.sensitive_data
      event.decrypt.sensitive_data.should_not eq(raw_data)
      event.sensitive_data["patient_id"].should be(nil)
      event.sensitive_data["foo"].should eq(1234)
      event.sensitive_data[:foo].should eq(1234)
    end

    it "uses the last version of the manifest" do
      Manifest.create definition: %{{
        "metadata" : {
          "device_models" : ["#{device.device_model.name}"],
          "version" : 1
        },
        "field_mapping" : [
          {
            "target_field": "foo",
            "selector" : "assay.name",
            "type" : "core"
          }
        ]
      }}

      Manifest.create definition: %{{
        "metadata" : {
          "device_models" : ["#{device.device_model.name}"],
          "version" : 2
        },
        "field_mapping" : [
          {
            "target_field": "assay_name",
            "selector" : "assay.name",
            "type" : "core"
          }
        ]
      }}

      post :create, Oj.dump(assay: {name: "GX4002"}, patient_id: 1234), device_uuid: device.secret_key

      event = all_elasticsearch_events.first["_source"]
      event["foo"].should be(nil)
      event["assay_name"].should eq("GX4002")
    end

    it "stores custom fields according to the manifest" do
      Manifest.create definition: %{{
        "metadata" : {
          "device_models" : ["#{device.device_model.name}"],
          "version" : 2
        },
        "field_mapping" : [
          {
            "target_field": "foo",
            "selector" : "some_field",
            "type" : "custom",
            "pii": false,
            "indexed": false
          }
        ]
      }}

      post :create, Oj.dump(some_field: 1234), device_uuid: device.secret_key

      event = all_elasticsearch_events.first["_source"]
      event["foo"].should be(nil)

      event = Event.first.decrypt
      event.sensitive_data["some_field"].should be(nil)
      event.sensitive_data["foo"].should be(nil)
      event.custom_fields[:foo].should eq(1234)
      event.custom_fields["foo"].should eq(1234)
    end
  end

  context "locations" do
    let(:root_location) {Location.make}
    let(:parent_location) {Location.make parent: root_location}
    let(:leaf_location1) {Location.make parent: parent_location}
    let(:leaf_location2) {Location.make parent: parent_location}
    let(:upper_leaf_location) {Location.make parent: root_location}
    let(:laboratory1) {Laboratory.make institution: institution, location: leaf_location1}
    let(:laboratory2) {Laboratory.make institution: institution, location: leaf_location2}
    let(:laboratory3) {Laboratory.make institution: institution, location: upper_leaf_location}

    it "should store the location id when the device is registered in only one laboratory" do
      device.laboratories = [laboratory1]
      device.save!
      post :create, data, device_uuid: device.secret_key

      event = all_elasticsearch_events.first["_source"]
      event["location_id"].should eq(leaf_location1.id)
      event["laboratory_id"].should eq(laboratory1.id)
      event["parent_locations"].sort.should eq([leaf_location1.id, parent_location.id, root_location.id].sort)
    end

    it "should store the parent location id when the device is registered more than one laboratory" do
      device.laboratories = [laboratory2, laboratory3]
      device.save!

      post :create, data, device_uuid: device.secret_key

      event = all_elasticsearch_events.first["_source"]
      event["location_id"].should eq(root_location.id)
      event["laboratory_id"].should be(nil)
      event["parent_locations"].should eq([root_location.id])
    end

    it "should store the parent location id when the device is registered more than one laboratory with another tree order" do
      device.laboratories = [laboratory3, laboratory2]
      device.save!

      post :create, data, device_uuid: device.secret_key

      event = all_elasticsearch_events.first["_source"]
      event["location_id"].should eq(root_location.id)
      event["laboratory_id"].should be(nil)
      event["parent_locations"].should eq([root_location.id])
    end

    it "should store nil if no location was found" do
      device.laboratories = []
      device.save!

      post :create, data, device_uuid: device.secret_key

      event = all_elasticsearch_events.first["_source"]
      event["location_id"].should be(nil)
      event["laboratory_id"].should be(nil)
      event["parent_locations"].should eq([])
    end

    it "filters by location" do
      device1 = Device.make institution: institution, laboratories: [laboratory1]
      device2 = Device.make institution: institution, laboratories: [laboratory2]
      device3 = Device.make institution: institution, laboratories: [laboratory3]
      post :create, (Oj.dump results:[result: "negative"]), device_uuid: device1.secret_key
      post :create, (Oj.dump results:[result: "positive"]), device_uuid: device2.secret_key
      post :create, (Oj.dump results:[result: "positive with riff"]), device_uuid: device3.secret_key

      response = get_updates(location: leaf_location1.id)

      response.first["results"].first["result"].should eq("negative")

      response = get_updates(location: leaf_location2.id)

      response.first["results"].first["result"].should eq("positive")

      response = get_updates(location: parent_location.id).sort_by do |event|
        event["results"].first["result"]
      end

      response.size.should be(2)
      response[0]["results"].first["result"].should eq("negative")
      response[1]["results"].first["result"].should eq("positive")

      response = get_updates(location: root_location.id).sort_by do |event|
        event["results"].first["result"]
      end

      response.size.should be(3)
      response[0]["results"].first["result"].should eq("negative")
      response[1]["results"].first["result"].should eq("positive")
      response[2]["results"].first["result"].should eq("positive with riff")
    end
  end

  context "Query" do
    context "Filter" do
      let(:device2) {Device.make institution: institution}

      it "should check for new events since a date" do
        Timecop.freeze(Time.utc(2013, 1, 1, 12, 0, 0))
        post :create, data, device_uuid: device.secret_key
        Timecop.freeze(Time.utc(2013, 1, 2, 12, 0, 0))
        post :create, (Oj.dump results:[result: :negative]), device_uuid: device.secret_key

        response = get_updates(since: Time.utc(2013, 1, 2, 12, 0, 0).utc.iso8601)

        response.size.should be(1)
        response.first["results"].first["result"].should eq("negative")

        response = get_updates(since: Time.utc(2013, 1, 1, 12, 0, 0).utc.iso8601)

        response.first["results"].first["result"].should eq("positive")
        response.last["results"].first["result"].should eq("negative")

        get_updates(since: Time.utc(2013, 1, 3, 12, 0, 0).utc.iso8601).should be_empty
      end


      it "should check for new events util a date" do
        Timecop.freeze(Time.utc(2013, 1, 1, 12, 0, 0))
        post :create, data, device_uuid: device.secret_key
        Timecop.freeze(Time.utc(2013, 1, 3, 12, 0, 0))
        post :create, (Oj.dump results:[result: :negative]), device_uuid: device.secret_key

        response = get_updates(:until => Time.utc(2013, 1, 2, 12, 0, 0).utc.iso8601)

        response.size.should be(1)
        response.first["results"].first["result"].should eq("positive")
      end

      it "should filter by device" do
        post :create, data, device_uuid: device.secret_key
        post :create, (Oj.dump results:[result: :negative]), device_uuid: device2.secret_key

        response = get_updates(device: device.secret_key)

        response.size.should be(1)
        response.first["results"].first["result"].should eq("positive")
      end

      it "filters by laboratory" do
        post :create, data, device_uuid: device.secret_key
        post :create, (Oj.dump results:[result: :negative]), device_uuid: device2.secret_key

        response = get_updates(laboratory: device2.laboratories.first.id)

        response.size.should be(1)
        response.first["results"].first["result"].should eq("negative")
      end

      it "should filter by institution" do
        post :create, data, device_uuid: device.secret_key
        device3 = Device.make
        post :create, (Oj.dump results:[result: :negative]), device_uuid: device3.secret_key
        client = Elasticsearch::Client.new log: true
        client.indices.refresh index: device3.institution.elasticsearch_index_name

        response = get_updates(institution: device3.institution.id)

        response.size.should be(1)
        response.first["results"].first["result"].should eq("negative")
      end

      it "should filter by gender" do
        post :create, (Oj.dump results:[result: :positive], gender: "male"), device_uuid: device.secret_key
        post :create, (Oj.dump results:[result: :negative], gender: "female"), device_uuid: device.secret_key

        response = get_updates(gender: "male")

        response.size.should be(1)
        response.first["results"].first["result"].should eq("positive")

        response = get_updates(gender: "female")

        response.size.should be(1)
        response.first["results"].first["result"].should eq("negative")
      end

      it "should filter by assay name" do
        post :create, (Oj.dump results:[result: :positive], assay_name: "GX4001"), device_uuid: device.secret_key
        post :create, (Oj.dump results:[result: :negative], assay_name: "GX1234"), device_uuid: device.secret_key

        response = get_updates(assay_name: "GX4001")

        response.size.should be(1)
        response.first["results"].first["result"].should eq("positive")

        response = get_updates(assay_name: "GX1234")

        response.size.should be(1)
        response.first["results"].first["result"].should eq("negative")
      end

      it "should filter by age" do
        post :create, (Oj.dump results:[result: :positive], age: 10), device_uuid: device.secret_key
        post :create, (Oj.dump results:[result: :negative], age: 20), device_uuid: device.secret_key

        response = get_updates(age: 10)

        response.size.should be(1)
        response.first["results"].first["result"].should eq("positive")

        response = get_updates(age: 20)

        response.size.should be(1)
        response.first["results"].first["result"].should eq("negative")

        response = get_updates(age: 15)
        response.size.should be(0)
      end

      it "filters by min age" do
        post :create, (Oj.dump results:[result: :positive], age: 10), device_uuid: device.secret_key
        post :create, (Oj.dump results:[result: :negative], age: 20), device_uuid: device.secret_key

        response = get_updates(min_age: 15)

        response.size.should be(1)
        response.first["results"].first["result"].should eq("negative")

        response = get_updates(min_age: 20)

        response.size.should be(1)
        response.first["results"].first["result"].should eq("negative")

        response = get_updates(min_age: 21)
        response.size.should be(0)
      end

      it "filters by max age" do
        post :create, (Oj.dump results:[result: :positive], age: 10), device_uuid: device.secret_key
        post :create, (Oj.dump results:[result: :negative], age: 20), device_uuid: device.secret_key

        response = get_updates(max_age: 15)

        response.size.should be(1)
        response.first["results"].first["result"].should eq("positive")

        response = get_updates(max_age: 10)

        response.size.should be(1)
        response.first["results"].first["result"].should eq("positive")

        response = get_updates(max_age: 9)
        response.size.should be(0)
      end

      it "filters by result" do
        post :create, (Oj.dump results:[condition: "MTB", result: :positive], age: 10), device_uuid: device.secret_key
        post :create, (Oj.dump results:[condition: "Flu", result: :negative], age: 20), device_uuid: device.secret_key

        response = get_updates(result: :positive)

        response.size.should be(1)
        response.first["age"].should eq(10)
      end

      it "filters by uuid" do
        post :create, (Oj.dump results:[result: :positive], assay_name: "GX4001"), device_uuid: device.secret_key
        post :create, (Oj.dump results:[result: :negative], assay_name: "GX1234"), device_uuid: device.secret_key

        response = get_updates(assay_name: "GX4001")
        response = get_updates(uuid: response.first["uuid"])

        response.size.should be(1)
        response.first["results"].first["result"].should eq("positive")

        response = get_updates(assay_name: "GX1234")
        response = get_updates(uuid: response.first["uuid"])

        response.size.should be(1)
        response.first["results"].first["result"].should eq("negative")
      end

      it "filters by a partial match" do
        post :create, (Oj.dump results:[result: :positive], assay_name: "GX4001"), device_uuid: device.secret_key
        post :create, (Oj.dump results:[result: :negative], assay_name: "GX1234"), device_uuid: device.secret_key

        response = get_updates(assay_name: "GX1*")
        response.size.should be(1)
        response.first["results"].first["result"].should eq("negative")
      end

      it "filters by condition name" do
        post :create, (Oj.dump results:[condition: "MTB", result: :positive]), device_uuid: device.secret_key
        post :create, (Oj.dump results:[condition: "Flu", result: :negative]), device_uuid: device.secret_key

        response = get_updates(condition: "MTB")

        response.size.should be(1)
        response.first["results"].first["result"].should eq("positive")

        response = get_updates(condition: "Flu")

        response.size.should be(1)
        response.first["results"].first["result"].should eq("negative")
      end

      # it "filters by an analyzed result" do
      #   post :create, (Oj.dump results:[condition: "MTB", result: :negative]), device_uuid: device.secret_key
      #   post :create, (Oj.dump results:[condition: "MTB", result: "Positive with RIFF resistance"]), device_uuid: device.secret_key

      #   response = get_updates(result: :positive)

      #   response.size.should be(1)
      #   response.first["results"].first["result"].should eq("Positive with RIFF resistance")
      # end

      it "filters by result, age and condition" do
        post :create, (Oj.dump results:[condition: "MTB", result: :positive], age: 20), device_uuid: device.secret_key
        post :create, (Oj.dump results:[condition: "MTB", result: :negative], age: 20), device_uuid: device.secret_key
        post :create, (Oj.dump results:[condition: "Flu", result: :negative], age: 20), device_uuid: device.secret_key

        response = get_updates(result: :negative, age: 20, condition: "Flu")

        response.size.should be(1)
        response.first["results"].first["result"].should eq("negative")
      end
    end

    context "Grouping" do
      it "groups by gender" do
        post :create, (Oj.dump results:[result: :positive], gender: :male), device_uuid: device.secret_key
        post :create, (Oj.dump results:[result: :negative], gender: :male), device_uuid: device.secret_key
        post :create, (Oj.dump results:[result: :negative], gender: :female), device_uuid: device.secret_key

        response = get_updates(group_by: :gender).sort_by do |event|
          event["gender"]
        end

        response.should eq([
          {"gender"=>"female", "count"=>1},
          {"gender"=>"male", "count"=>2}
        ])
      end

      it "groups by gender in post body" do
        post :create, (Oj.dump results:[result: :positive], gender: :male), device_uuid: device.secret_key
        post :create, (Oj.dump results:[result: :negative], gender: :male), device_uuid: device.secret_key
        post :create, (Oj.dump results:[result: :negative], gender: :female), device_uuid: device.secret_key

        response = get_updates({}, Oj.dump(group_by: :gender)).sort_by do |event|
          event["gender"]
        end

        response.should eq([
          {"gender"=>"female", "count"=>1},
          {"gender"=>"male", "count"=>2}
        ])
      end

      it "groups by gender and assay_name" do
        post :create, (Oj.dump results:[result: :positive], gender: :male, assay_name: "a"), device_uuid: device.secret_key
        post :create, (Oj.dump results:[result: :positive], gender: :male, assay_name: "a"), device_uuid: device.secret_key
        post :create, (Oj.dump results:[result: :positive], gender: :male, assay_name: "b"), device_uuid: device.secret_key
        post :create, (Oj.dump results:[result: :negative], gender: :female, assay_name: "a"), device_uuid: device.secret_key
        post :create, (Oj.dump results:[result: :negative], gender: :female, assay_name: "b"), device_uuid: device.secret_key
        post :create, (Oj.dump results:[result: :negative], gender: :female, assay_name: "b"), device_uuid: device.secret_key

        response = get_updates(group_by: "gender,assay_name").sort_by do |event|
          event["gender"] + event["assay_name"]
        end

        response.should eq([
          {"gender"=>"female", "assay_name" => "a", "count"=>1},
          {"gender"=>"female", "assay_name" => "b", "count"=>2},
          {"gender"=>"male", "assay_name" => "a", "count"=>2},
          {"gender"=>"male", "assay_name" => "b", "count"=>1}
        ])
      end

      it "groups by gender and assay_name in post body" do
        post :create, (Oj.dump results:[result: :positive], gender: :male, assay_name: "a"), device_uuid: device.secret_key
        post :create, (Oj.dump results:[result: :positive], gender: :male, assay_name: "a"), device_uuid: device.secret_key
        post :create, (Oj.dump results:[result: :positive], gender: :male, assay_name: "b"), device_uuid: device.secret_key
        post :create, (Oj.dump results:[result: :negative], gender: :female, assay_name: "a"), device_uuid: device.secret_key
        post :create, (Oj.dump results:[result: :negative], gender: :female, assay_name: "b"), device_uuid: device.secret_key
        post :create, (Oj.dump results:[result: :negative], gender: :female, assay_name: "b"), device_uuid: device.secret_key

        response = get_updates({}, Oj.dump(group_by: [:gender , :assay_name])).sort_by do |event|
          event["gender"] + event["assay_name"]
        end

        response.should eq([
          {"gender"=>"female", "assay_name" => "a", "count"=>1},
          {"gender"=>"female", "assay_name" => "b", "count"=>2},
          {"gender"=>"male", "assay_name" => "a", "count"=>2},
          {"gender"=>"male", "assay_name" => "b", "count"=>1}
        ])
      end

      it "groups by gender, assay_name and result" do
        post :create, (Oj.dump results:[result: :positive], gender: :male, assay_name: "a"), device_uuid: device.secret_key
        post :create, (Oj.dump results:[result: :negative], gender: :male, assay_name: "a"), device_uuid: device.secret_key
        post :create, (Oj.dump results:[result: :positive], gender: :male, assay_name: "b"), device_uuid: device.secret_key
        post :create, (Oj.dump results:[result: :negative], gender: :female, assay_name: "a"), device_uuid: device.secret_key
        post :create, (Oj.dump results:[result: :negative], gender: :female, assay_name: "b"), device_uuid: device.secret_key
        post :create, (Oj.dump results:[result: :negative], gender: :female, assay_name: "b"), device_uuid: device.secret_key

        response = get_updates(group_by: "gender,assay_name,result").sort_by do |event|
          event["gender"] + event["result"] + event["assay_name"]
        end

        response.should eq([
          {"gender"=>"female", "result" => "negative", "assay_name" => "a", "count"=>1},
          {"gender"=>"female", "result" => "negative", "assay_name" => "b", "count"=>2},
          {"gender"=>"male", "result" => "negative", "assay_name" => "a", "count"=>1},
          {"gender"=>"male", "result" => "positive", "assay_name" => "a", "count"=>1},
          {"gender"=>"male", "result" => "positive", "assay_name" => "b", "count"=>1}
        ])
      end

      it "groups by gender, assay_name and result in a different order" do
        post :create, (Oj.dump results:[result: :positive], gender: :male, assay_name: "a"), device_uuid: device.secret_key
        post :create, (Oj.dump results:[result: :negative], gender: :male, assay_name: "a"), device_uuid: device.secret_key
        post :create, (Oj.dump results:[result: :positive], gender: :male, assay_name: "b"), device_uuid: device.secret_key
        post :create, (Oj.dump results:[result: :negative], gender: :female, assay_name: "a"), device_uuid: device.secret_key
        post :create, (Oj.dump results:[result: :negative], gender: :female, assay_name: "b"), device_uuid: device.secret_key
        post :create, (Oj.dump results:[result: :negative], gender: :female, assay_name: "b"), device_uuid: device.secret_key

        response = get_updates(group_by: "result,gender,assay_name").sort_by do |event|
          event["gender"] + event["result"] + event["assay_name"]
        end

        response.should eq([
          {"gender"=>"female", "result" => "negative", "assay_name" => "a", "count"=>1},
          {"gender"=>"female", "result" => "negative", "assay_name" => "b", "count"=>2},
          {"gender"=>"male", "result" => "negative", "assay_name" => "a", "count"=>1},
          {"gender"=>"male", "result" => "positive", "assay_name" => "a", "count"=>1},
          {"gender"=>"male", "result" => "positive", "assay_name" => "b", "count"=>1}
        ])
      end

      # it "group by year(date)" do
      #   create_event [results: [result: "positive"]], {{2010,1,1},{12,0,0}}
      #   create_event [results: [result: "positive"]], {{2010,1,2},{12,0,0}}
      #   create_event [results: [result: "positive"]], {{2011,1,1},{12,0,0}}

      #   response = get_updates("group_by=#{escape("year(created_at)")}")
      #   response = Enum.sort response, fn(r1, r2) -> r1["created_at"] < r2["created_at"] end

      #   assert_all_values response, ["created_at", "count"], [
      #     ["2010", 2],
      #     ["2011", 1],
      #   ]
      # end

      # it "group by month(date)" do
      #   create_event [results: [result: "positive"]], {{2010,1,1},{12,0,0}}
      #   create_event [results: [result: "positive"]], {{2010,2,2},{12,0,0}}
      #   create_event [results: [result: "positive"]], {{2011,1,1},{12,0,0}}
      #   create_event [results: [result: "positive"]], {{2011,1,2},{12,0,0}}
      #   create_event [results: [result: "positive"]], {{2011,2,1},{12,0,0}}

      #   response = get_updates("group_by=#{escape("month(created_at)")}")
      #   response = Enum.sort response, fn(r1, r2) -> r1["created_at"] < r2["created_at"] end

      #   assert_all_values response, ["created_at", "count"], [
      #     ["2010-01", 1],
      #     ["2010-02", 1],
      #     ["2011-01", 2],
      #     ["2011-02", 1],
      #     ]
      # end

      # it "group by week(date)" do
      #   create_event [results: [result: "positive"]], {{2010,1,4},{12,0,0}}
      #   create_event [results: [result: "positive"]], {{2010,1,5},{12,0,0}}
      #   create_event [results: [result: "positive"]], {{2010,1,6},{12,0,0}}
      #   create_event [results: [result: "positive"]], {{2010,1,12},{12,0,0}}
      #   create_event [results: [result: "positive"]], {{2010,1,13},{12,0,0}}

      #   response = get_updates("group_by=#{escape("week(created_at)")}")
      #   response = Enum.sort response, fn(r1, r2) -> r1["created_at"] < r2["created_at"] end

      #   assert_all_values response, ["created_at", "count"], [
      #     ["2010-W1", 3],
      #     ["2010-W2", 2],
      #     ]
      # end

      # it "group by day(date)" do
      #   create_event [results: [result: "positive"]], {{2010,1,4},{12,0,0}}
      #   create_event [results: [result: "positive"]], {{2010,1,4},{13,0,0}}
      #   create_event [results: [result: "positive"]], {{2010,1,4},{14,0,0}}
      #   create_event [results: [result: "positive"]], {{2010,1,5},{12,0,0}}

      #   response = get_updates("group_by=#{escape("day(created_at)")}")
      #   response = Enum.sort response, fn(r1, r2) -> r1["created_at"] < r2["created_at"] end

      #   assert_all_values response, ["created_at", "count"], [
      #     ["2010-01-04", 3],
      #     ["2010-01-05", 1],
      #     ]
      # end

      # it "group by day(date) and result" do
      #   create_event [results: [result: "positive"]], {{2010,1,4},{12,0,0}}
      #   create_event [results: [result: "positive"]], {{2010,1,4},{13,0,0}}
      #   create_event [results: [result: "negative"]], {{2010,1,4},{14,0,0}}
      #   create_event [results: [result: "positive"]], {{2010,1,5},{12,0,0}}

      #   response = get_updates("group_by=#{escape("day(created_at)")},result")
      #   response = Enum.sort response, fn(r1, r2) ->
      #     if r1["created_at"] == r2["created_at"] do
      #       r1["result"] < r2["result"]
      #     else
      #       r1["created_at"] < r2["created_at"]
      #     end
      #   end

      #   assert_all_values response, ["created_at", "result", "count"], [
      #     ["2010-01-04", "negative", 1],
      #     ["2010-01-04", "positive", 2],
      #     ["2010-01-05", "positive", 1],
      #     ]
      # end

      # it "group by age ranges" do
      #   post_event age: 9
      #   post_event age: 10
      #   post_event age: 11
      #   post_event age: 12
      #   post_event age: 13
      #   post_event age: 20
      #   post_event age: 21

      #   response = get_updates("", JSEX.encode!([
      #     group_by: [
      #       ["age", [[0, 10], [15, 120], [10, 15]]]
      #     ]
      #   ]))
      #   response = Enum.sort response, fn(r1, r2) -> r1["age"] < r2["age"] end

      #   assert_all_values response, ["age", "count"], [
      #     [[ 0,  10], 1],
      #     [[10,  15], 4],
      #     [[15, 120], 2],
      #     ]
      # end

      # it "group by age ranges in a different way" do
      #   post_event age: 9
      #   post_event age: 10
      #   post_event age: 11
      #   post_event age: 12
      #   post_event age: 13
      #   post_event age: 20
      #   post_event age: 21

      #   response = get_updates("", JSEX.encode!([
      #     group_by: ["age", [[0, 10], [15, 120], [10, 15]]]
      #   ]))
      #   response = Enum.sort response, fn(r1, r2) -> r1["age"] < r2["age"] end

      #   assert_all_values response, ["age", "count"], [
      #     [[ 0,  10], 1],
      #     [[10,  15], 4],
      #     [[15, 120], 2],
      #     ]
      # end

      # it "group by results result" do
      #   post_event results: [[condition: "MTB", result: "positive"], [condition: "Flu", result: "negative"]]

      #   response = get_updates("group_by=result")
      #   response = Enum.sort response, fn(r1, r2) -> r1["result"] < r2["result"] end

      #   assert_all_values response, ["result", "count"], [
      #     ["negative", 1],
      #     ["positive", 1],
      #   ]
      # end

      # it "group by results result and condition" do
      #   post_event results: [[condition: "MTB", result: "positive"], [condition: "Flu", result: "negative"]]

      #   response = get_updates("group_by=result,condition")
      #   response = Enum.sort response, fn(r1, r2) -> r1["result"] < r2["result"] end

      #   assert_all_values response, ["condition", "result", "count"], [
      #     ["Flu", "negative", 1],
      #     ["MTB", "positive", 1],
      #   ]
      # end

      # it "group by a non indexed field raises an error" do
      #   post_event results: [[condition: "MTB", result: "positive"], [condition: "Flu", result: "negative"]]

      #   assert_raise RuntimeError, "Trying to group by a non searchable field", fn ->
      #     get_updates("group_by=foo")
      #   end
      # end

    end
  end
end