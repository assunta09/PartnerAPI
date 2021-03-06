class Organisation < ApplicationRecord
  has_many :executives
  has_many :balances
  has_many :revenues # organisations have a one-to-many relationship with revenues and expenses to allow
  has_many :expenses # analysis over several years in the future
  has_many :program_service_accomplishments
  belongs_to :masterfile

  def rendering
    #This method renders the organisations general data as needed for the frontend
    organisation_data = self.attributes

    #Ger rid of attributes in the organisations table that are not needed
    ['created_at', 'updated_at', 'ein','masterfile_id'].each do |item_to_delete|
      organisation_data.delete(item_to_delete)
    end
    #The address needs to re-formated and we have to get the coordinates for the address
    address_new = organisation_data["address"].join(' ')
    geolocation = get_geocoding(address_new)
    location = [geolocation.first[:latitude], geolocation.first[:longitude]]
    organisation_data["address"] = address(location, address_new)

    #Add some extra fields to the general information section
    organisation_data[:tax_year] = expense_data.year
    organisation_data[:geocoding] = geolocation
    organisation_data
  end

# Method for geocoding
  def get_geocoding(address)
    location = Geocoder.search(address)
    [latitude: location[0].latitude, longitude: location[0].longitude]
  end

#Method for reverse geocoding, i.e. getting a nicely formatted address
  def address(location, address_new)
    if location.present?
      Geocoder.address(location)
    else
      address_new
    end
  end

#Returns fund-raising fees and funds raised needed to display fund-raising ratio
  def fundraising_ratio
    fundraising_ratio = {fundraising_fees: expense_data.fundraising_fees.to_i, funds_raised: Contribution.find(revenue_data.contribution_id).fundraising.to_i}
  end

  # returns expenses overview
  # found in Part I lines 13-19 from IRS990 form
  def general_expenses_absolutes
    expense_split = {}
    expense_data.attributes.each do |expense_type, value|
      if expense_type == 'member_benefits' || expense_type == 'fundraising_fees' || expense_type == 'total'
        expense_split[expense_type] = value.to_i
      elsif expense_type == 'salary_id'
        salary_data = Salary.find(value)
        expense_split['salaries'] = salary_data.total.to_i
      elsif expense_type == 'grant_id'
        grant_data = Grant.find(value)
        expense_split['grant'] = grant_data.total.to_i
      elsif expense_type == 'other_expense_id'
        other_expenses_data = OtherExpense.find(value)
        expense_split['other_expenses'] = other_expenses_data.total.to_i
      end
    end
    expense_split
  end

  # returns revenue overview
  # found in Part I lines 8-12 from IRS990 form
  def general_revenue_absolutes
    revenue_split = {}
    revenue_data.attributes.each do |revenue_type, value|
      if revenue_type == 'service_revenue' || revenue_type == 'investments' || revenue_type == 'other' || revenue_type == 'total'
        revenue_split[revenue_type] = value.to_i
      elsif revenue_type == "contribution_id"
        contribution_data = Contribution.find(value)
        revenue_split['contribution'] = contribution_data.total.to_i
      end
    end
    revenue_split
  end

  # returns breakdown of other expenses for an organisation
  # found in Part IX, column (a), lines 11a-11d, 11f-24e in IRS990 form
  def other_expenses_absolutes
    other_expense_split = {}
    other_expense_data = OtherExpense.find(expense_data.other_expense_id)

    other_expense_data.attributes.each do |expense_type, value|
      if expense_type != 'total' && expense_type != 'id' && expense_type != 'created_at' && expense_type != 'updated_at'
          other_expense_split[expense_type] = value.to_i
      end
    end
    other_expense_split
  end

  # return information about compensation for each reported individual
  # this information is found in Part VII of the IRS990 form
  def salaries_absolutes
    salary_split = {}
    salary_data = Salary.find(expense_data.salary_id)

    salary_data.attributes.each do |expense_type, value|
      if expense_type != 'total' && expense_type != 'id' && expense_type != 'created_at' && expense_type != 'updated_at'
        salary_split[expense_type] = value.to_i
      end
    end
    salary_split
  end

  # returns information found in Part IX, column (A), lines 1-3 in IRS990 form
  def grants_absolutes
    grant_split = {}
    grant_data = Grant.find(expense_data.grant_id)

    grant_data.attributes.each do |expense_type, value|
      if expense_type != 'total' && expense_type != 'id' && expense_type != 'created_at' && expense_type != 'updated_at'
          grant_split[expense_type] = value.to_i
      end
    end
    grant_split
  end

  # return information found in Part VIII, lines 1a-f in IRS990 form
  def contributions_absolutes
    contribution_split = {}
    contribution_data = Contribution.find(revenue_data.contribution_id)

    contribution_data.attributes.each do |revenue_type, value|
      if revenue_type != 'total' && revenue_type != 'id' && revenue_type != 'created_at' && revenue_type != 'updated_at'
        contribution_split[revenue_type] = value.to_i
      end
    end
    contribution_split
  end

  def revenues_split_absolutes
    array = [general_revenue_absolutes, contributions_absolutes]
    revenue_split = array.inject(:update)
    revenue_split.delete('contribution')
    ['contribution', 'total'].each do |item_to_delete|
      revenue_split.delete(item_to_delete)
    end
    revenue_split
  end

  def expenses_split_absolutes
    different_expense_types = [general_expenses_absolutes, salaries_absolutes, grants_absolutes, other_expenses_absolutes]
    expense_split = different_expense_types.inject(:update)
    ['salaries','grant', 'other_expenses', 'total'].each do |item_to_delete|
      expense_split.delete(item_to_delete)
    end
    expense_split
  end

  # returns the top three highest paid individuals for each organization
  # this information is found in Part VII of the IRS990 form
  def top_salaries_absolutes
    exec_salaries = Executive.where(organisation_id: self.id)
    sort_salaries = exec_salaries.sort_by{|k| (k["salary"] + k["other_salary"])}.reverse
    top_salaries = []
    sort_salaries[0...3].each do |executive|
      total_salary = executive.salary + executive.other_salary
      if total_salary != 0
        top_salaries << {name: executive.name, title: executive.title, salary: total_salary}
      end
    end
    top_salaries
  end

  # returns organisation's three largest program services as measured by expenses
  # found in part III 4a-c from IRS990 form
  def render_program_service_accomplishments
    psa_get_data = ProgramServiceAccomplishment.where(organisation_id: self.id)
    program_service_accomplishments = []

    psa_get_data.each do |accomplishment|
      program_service_accomplishments << {
        expense_amount: accomplishment.expense_amount.to_i,
        grant_amount: accomplishment.grant_amount.to_i,
        revenues: accomplishment.revenues.to_i,
        description: accomplishment.description}
    end
    program_service_accomplishments
  end

  private
  def expense_data
    expenses = Expense.where(organisation_id: self.id).first
  end

  def revenue_data
    revenues = Revenue.where(organisation_id: self.id).first
  end

end
