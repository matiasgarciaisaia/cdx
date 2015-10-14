require "spec_helper"

describe EncounterIndexer, elasticsearch: true do

  let(:timestamp) {
    DateTime.now.utc.iso8601
  }

  let(:patient) do
    patient_core_fields = {
      "gender" => "male",
      "custom_fields" => {
        "hiv" => "positive"
      }
    }
    Patient.make(uuid: 'abc', core_fields: patient_core_fields)
  end

  let(:encounter) do
    encounter_core_fields = {
      "id" => "20",
      "start_time" => timestamp,
      "end_time" => timestamp
    }
    Encounter.make(uuid: 'def', patient: patient, core_fields: encounter_core_fields)
  end

  let(:indexer) { EncounterIndexer.new(encounter)}

  it "should index a document" do
    client = double(:es_client)
    allow_any_instance_of(EncounterIndexer).to receive(:client).and_return(client)

    expect(client).to receive(:index).with(
      index: Cdx::Api.index_name,
      type: "encounter",
      body: {
        "encounter" => {
          "id" => "20",
          "start_time" => timestamp,
          "end_time" => timestamp,
          "uuid" => "def"
        },
        "patient" => {
          "uuid" => patient.uuid,
          "gender" => "male",
          "custom_fields" => {
            "hiv" => "positive"
          }
        },
        "institution" => {
          "uuid" => encounter.institution.uuid
        }
      },
      id: encounter.uuid)

    indexer.index
  end
end
