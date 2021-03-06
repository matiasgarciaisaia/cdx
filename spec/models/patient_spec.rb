require 'spec_helper'

describe Patient do

  context "validations" do

    it "should make a valid patient" do
      expect(Patient.make_unsaved).to be_valid
    end

    context "on fields" do
      let(:patient) { Patient.make_unsaved }

      it "should support valid core fields" do
        patient.core_fields['gender'] = 'male'
        expect(patient).to be_valid
      end

      it "should support valid sensitive fields" do
        patient.plain_sensitive_data['name'] = 'John Doe'
        expect(patient).to be_valid
      end

      it "should validate invalid core fields" do
        patient.core_fields['gender'] = 'invalid'
        expect(patient).to be_invalid
      end

      it "should validate non existing core fields" do
        patient.core_fields['inexistent'] = 'value'
        expect(patient).to be_invalid
      end

      it "should validate non existing sensitive fields" do
        patient.plain_sensitive_data['inexistent'] = 'value'
        expect(patient).to be_invalid
      end

      it "should validate pii fields in core fields" do
        patient.core_fields['name'] = 'John Doe'
        expect(patient).to be_invalid
      end

      it "should validate non-pii fields in sensitive fields" do
        patient.plain_sensitive_data['gender'] = 'male'
        expect(patient).to be_invalid
      end

    end

  end

end
