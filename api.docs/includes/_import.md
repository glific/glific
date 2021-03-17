# Glific.Contacts.Import Module

## import_contacts(organization_id, group_label, opts \\ [])

The `import_contacts` method can be used for performing bulk add/update/deletion of provider contacts in the database.

The function operates on csv style formatted data. The CSV data needs to be of the following format:
```
name,phone,Language,opt_in,delete
test,9989329297,english,2021-03-09
test2,1111111111,hindi,2021-03-09,1
```
The method supports extracting this CSV data from three mechanisms: 
- file_path: A csv file location.
- raw data: Passing in the csv as raw data.
- url: A url from where the data can be downloaded as a csv.

The method operates on the following logic:
- If a row consists of delete column's value as 1, the particular contact is deleted from the database. If the contact is allready not present in the datbase, the function ignores the row.

- If a row is for a mobile number which does not exist in the databae and delete!=1, the contact is inserted in the databse.
  -- If the value of opt_in is a valid date-time, the contact is opted in with the provider (currently gupshup) and then added to the database
  -- If the value of opt_in is empty, the contact is only added to the database.

- If a row is for a mobile number which exists in the database and delete!=1, the contact information is updated in the database.


The method takes in the following parameters:
- organization_id: the organization for which the contacts have to be imported.
- group_label: The lavel of the group to which the contacts have to be added. The group is created, if a group by the provided label does not exist.
- opts: opts allows the following key-word arguments to be supplied:
    -- file_path: The file_path of the csv file
    -- url: The url of csv file.
    -- data: The csv as a string.
    -- date_format: The format of the opt_in in the CSV. Default `{YYYY}-{M}-{D}`

## Examples
`Import.import_contacts(1, "Group", file_path: "test.csv")`
`Import.import_contacts(1,"Group", url: "http://foo.com/bar.csv")`
`Import.import_contacts(1,"Group", data: "name,phone,Language,opt_in,delete\ntest2,1111111111,hindi,2021-03-09,1")`
`Import.import_contacts(1, "Group", file_path: "test.csv", date_format: "{YYYY}-{M}-{D}")`

