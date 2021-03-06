/*
    Copyright (c) 2014, Salesforce.com Foundation
    All rights reserved.
    
    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions are met:
    
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of the Salesforce.com Foundation nor the names of
      its contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.
 
    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
    "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT 
    LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS 
    FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE 
    COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, 
    INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, 
    BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; 
    LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER 
    CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT 
    LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN 
    ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE 
    POSSIBILITY OF SUCH DAMAGE.
*/
/**
* @author Salesforce.com Foundation
* @date 2014
* @description Tests for allocation multicurrency functionality. Will only run in active multicurrency orgs with multiple currencies active.
*/
@isTest
public class ALLO_Multicurrency_TEST {
    
    // if you only want to run one test in this class, fill in its name here.
    // if you want to run all tests, then use '*'
    private static string strTestOnly = '*';
    
    public static sObject nonDefaultCurrencyType;
    public static sObject defaultCurrencyType;

    public static void setupISOCodes() {
        if (nonDefaultCurrencyType!=null || defaultCurrencyType!=null)
            return;
        else {
            for (sObject ct : database.query('select IsoCode, ConversionRate, IsCorporate from CurrencyType')) {
                if ((boolean)ct.get('IsCorporate')) 
                    defaultCurrencyType = ct;
                else
                    nonDefaultCurrencyType = ct;
            }
        }
    }

    private static void setupSettings (Allocations_Settings__c alloset) {
        //set running user to avoid dml issue            
        System.runAs(new User(id = UserInfo.getUserId())){
            if (alloset!=null)
                UTIL_CustomSettingsFacade.getAllocationsSettingsForTests(alloset);
            else 
                UTIL_CustomSettingsFacade.getAllocationsSettingsForTests(new Allocations_Settings__c());

        }
    }

    //allocations inherit the currency of their parent
    //updating a parent updates the allocation currency
    //creating an opportunity with a different currency from the parent campaign converts the allocation amount to the opportunity's currency
    //user cannot manually update the currency of an allocation and must do so through the parent
    @isTest static void alloMultiCurrency() {
        if (strTestOnly != '*' && strTestOnly != 'alloMultiCurrency') return;

        //only run test in multicurrency orgs
        if (!userInfo.isMultiCurrencyOrganization())
            return;

        setupISOCodes();

        //if we don't have a non default currency, we can't run our test
        if (nonDefaultCurrencyType==null)
            return;

        setupSettings(null);

        Campaign cam = new Campaign(Name='foo', IsActive=true);
        insert cam;

        Account acc = new Account(Name='foo');
        insert acc;
        General_Accounting_Unit__c campaigngau = new General_Accounting_Unit__c(Name='foo');
        insert campaigngau;

        Allocation__c amountAllo = new Allocation__c(Campaign__c=cam.id, Amount__c = 5, General_Accounting_Unit__c = campaigngau.id);
        insert amountAllo;

        list<sObject> queryAllo = database.query('SELECT Id, CurrencyIsoCode FROM Allocation__c');
        system.assertEquals(defaultCurrencyType.get('IsoCode'), queryAllo[0].get('CurrencyIsoCode'), 'Allocation should have the default currency type.');

        cam.put('CurrencyIsoCode',nonDefaultCurrencyType.get('IsoCode'));
        update cam;

        queryAllo = database.query('SELECT Id, CurrencyIsoCode FROM Allocation__c');
        system.assertEquals(nonDefaultCurrencyType.get('IsoCode'), queryAllo[0].get('CurrencyIsoCode'), 'Allocation should have an updated non-default currency type.');

        ALLO_Allocations_TDTM.resetFlags(false);
        Opportunity opp = new Opportunity(Name='success', Amount = 10, AccountID=acc.id, CampaignId=cam.id, CloseDate=system.today(), StageName=UTIL_UnitTestData_TEST.getClosedWonStage());
        insert opp;

        decimal convertedAmount = ALLO_Multicurrency_TDTM.convertCurrency((string)nonDefaultCurrencyType.get('IsoCode'), (string)defaultCurrencyType.get('IsoCode'), 5);

        queryAllo = database.query('SELECT Id, Amount__c, CurrencyIsoCode FROM Allocation__c WHERE Opportunity__c != null');
        system.assertEquals(1,queryAllo.size(), 'Opportunity allocation should be automatically created from the Campaign allocation.');
        system.assertEquals(defaultCurrencyType.get('IsoCode'), queryAllo[0].get('CurrencyIsoCode'), 'Opportunity Allocation should have the default currency type.');
        system.assertEquals(convertedAmount, queryAllo[0].get('Amount__c'), 'Opportunity\'s automatically created allocation\'s amount should have be converted to the default currency type.');


        //update the currency manually, an exception should be thrown.
        ALLO_Allocations_TDTM.resetFlags(false);
        queryAllo[0].put('CurrencyIsoCode',nonDefaultCurrencyType.get('IsoCode'));

        Exception ex = null;
        try {
            update queryAllo[0];
        } catch (Exception e) {
            ex = e;
        }
        system.assertNotEquals(null,ex,'An exception should be caught.');
    }

    //rollups correcly convert amounts of different currencies in multicurrency orgs
    @isTest static void rollupMultiCurrency() {
        if (strTestOnly != '*' && strTestOnly != 'rollupMultiCurrency') return;

        //only run test in multicurrency orgs
        if (!userInfo.isMultiCurrencyOrganization())
            return;

        setupISOCodes();

        //if we don't have a non default currency, we can't run our test
        if (nonDefaultCurrencyType==null)
            return;

        setupSettings(null);

        Account acc = new Account(Name='foo');
        insert acc;
        
        list<Opportunity> oppsForInsert = new list<Opportunity>();
        oppsForInsert.add(new Opportunity(Name='foo', Amount = 8, AccountID=acc.id, CloseDate=system.today(), StageName=UTIL_UnitTestData_TEST.getClosedWonStage()));
        oppsForInsert.add(new Opportunity(Name='foo', Amount = 8, AccountID=acc.id, CloseDate=system.today().addYears(-2), StageName=UTIL_UnitTestData_TEST.getClosedWonStage()));
        oppsForInsert[1].put('CurrencyIsoCode', nonDefaultCurrencyType.get('IsoCode'));
        insert oppsForInsert;
        
        General_Accounting_Unit__c gau = new General_Accounting_Unit__c(Name='foo');
        insert gau;

        list<Allocation__c> alloForInsert = new list<Allocation__c>();
        alloForInsert.add(new Allocation__c(Opportunity__c=oppsForInsert[0].id, Amount__c = 8, General_Accounting_Unit__c = gau.id));
        alloForInsert.add(new Allocation__c(Opportunity__c=oppsForInsert[1].id, Amount__c = 8, General_Accounting_Unit__c = gau.id));
        ALLO_Allocations_TDTM.resetFlags(false);
        insert alloForInsert;

        id alloid = alloForInsert[1].id;

        list<Allocation__c> alloQuery = database.query('SELECT Id, Amount__c, CurrencyIsoCode FROM Allocation__c WHERE Id = :alloid');
        system.assertEquals(nonDefaultCurrencyType.get('IsoCode'),alloQuery[0].get('CurrencyIsoCode'),'Allocation should inherit the parent Opportunity currency code.');

        PageReference pageRef = Page.ALLO_RollupBTN;
        Test.setCurrentPage(pageRef);

        ALLO_RollupBTN_CTRL ctrl = new ALLO_RollupBTN_CTRL();
        ApexPages.currentPage().getParameters().put('id', gau.id);

        ctrl.buttonClick();

        list<General_Accounting_Unit__c> queryGAU = [SELECT Id, First_Allocation_Date__c, Largest_Allocation__c, Last_Allocation_Date__c, Number_of_Allocations_Last_N_Days__c, Number_of_Allocations_Last_Year__c, Number_of_Allocations_This_Year__c, 
                                                    Number_of_Allocations_Two_Years_Ago__c, Smallest_Allocation__c, Total_Allocations__c, Total_Allocations_Last_N_Days__c, Total_Allocations_Last_Year__c, Total_Allocations_This_Year__c, 
                                                    Total_Allocations_Two_Years_Ago__c, Total_Number_of_Allocations__c FROM General_Accounting_Unit__c WHERE Id = :gau.id];
        system.debug('LookHere: queryGAU ' + queryGAU);
        
        decimal convertedAmount = ALLO_Multicurrency_TDTM.convertCurrency((string)nonDefaultCurrencyType.get('IsoCode'), (string)defaultCurrencyType.get('IsoCode'), 8);

        system.assertEquals(8+convertedAmount, queryGAU[0].Total_Allocations__c, 'Total allocations should equal 16.');
        system.assertEquals(system.today(), queryGAU[0].Last_Allocation_Date__c, 'Last allocation should be today.');
        system.assertEquals(system.today().addYears(-2), queryGAU[0].First_Allocation_Date__c, 'First allocation should be two years ago.');
        system.assertEquals(8, queryGAU[0].Total_Allocations_This_Year__c, 'Total allocations this year should equal 8.');
        system.assertEquals(0, queryGAU[0].Total_Allocations_Last_Year__c, 'Total allocations this year should equal 0.');
        system.assertEquals(convertedAmount, queryGAU[0].Total_Allocations_Two_Years_Ago__c, 'Total allocations two years ago should equal 8.');
        system.assertEquals(8, queryGAU[0].Total_Allocations_Last_N_Days__c, 'Total allocations last 365 days should equal 8.');
    }

    static void testMakeDefaultAllocations() {
        if (strTestOnly != '*' && strTestOnly != 'testMakeDefaultAllocations') return;
        
        //only run test in multicurrency orgs
        if (!userInfo.isMultiCurrencyOrganization())
            return;

        setupISOCodes();

        //if we don't have a non default currency, we can't run our test
        if (nonDefaultCurrencyType==null)
            return;

        General_Accounting_Unit__c defaultGau = new General_Accounting_Unit__c(Name='General');
        insert defaultGau;

        setupSettings(null);

        Account acc = new Account(Name='foo');
        insert acc;
        Opportunity opp = new Opportunity(Name='foo', Amount = 8, AccountID=acc.id, CloseDate=system.today(), StageName=UTIL_UnitTestData_TEST.getClosedWonStage());
        opp.put('CurrencyIsoCode', nonDefaultCurrencyType.get('IsoCode'));
        insert opp;

        list<Allocation__c>  queryAllo = [SELECT Id, Amount__c, Percent__c, General_Accounting_Unit__c FROM Allocation__c];
        system.assertEquals(0,queryAllo.size(), 'No default allocation should be created.');

        setupSettings(new Allocations_Settings__c(Default_Allocations_Enabled__c = true, Default__c = defaultGau.id));

        Test.startTest();
        id batchProcessId = database.executeBatch(new ALLO_MakeDefaultAllocations_BATCH());
        Test.stopTest();

        list<Allocation__c> alloQuery = database.query('SELECT Id, Amount__c, CurrencyIsoCode FROM Allocation__c WHERE Opportunity__c = :opp.id');
        system.assertEquals(1,alloQuery.size(), 'A default allocation should be created.');
        system.assertEquals(nonDefaultCurrencyType.get('IsoCode'),alloQuery[0].get('CurrencyIsoCode'),'Allocation should inherit the parent Opportunity currency code.');
        
        system.assertEquals(8, alloQuery[0].Amount__c, 'The default allocation should be of the total amount of the Opportunity.');
    }
}