/*
    Copyright (c) 2012, Salesforce.com Foundation
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
* @date 2012 (2.0)
* @description Class provides a batchable wrapper for open ended recurring donations
*/
public without sharing class RD_RecurringDonations_BATCH implements Database.Batchable<sObject>, Database.Stateful, 
UTIL_MasterSchedulableHelper.UTIL_IRecurring {
	
    public String query { get; set; } 
    public Integer recCount = 0;
    public Integer failuresCount = 0;
    
    public RD_RecurringDonations_BATCH() {
    	query = RD_RecurringDonations.strQueryRDNoWhere();
        query += ' where npe03__Open_Ended_Status__c = \'' + system.label.npe03.RecurringDonationOpenStatus + '\'';
    	RD_ProcessControl.batchButton = true;
    }
        
    public Boolean executeReturnStatus() {
        if(UTIL_JobScheduler.canRunBatch()) {
            Id batchInstanceId = Database.executeBatch(this, 50); 
            return true;
        }
        return false;
    }
    
    public database.Querylocator start(Database.BatchableContext bc){
        //clear any existing errors from the queue?
        //now with our error log, DJH thinks we should leave the errors alone.
        //delete [select id from Error__c where Context_Type__c = 'RD'];
        return Database.getQueryLocator(query);      
    }
    public void execute(Database.BatchableContext bc, Sobject[] result){
    	Savepoint sp = Database.setSavepoint();
        try {
	        RD_ProcessControl.batchButton = true;
	        recCount += result.size();
	        failuresCount = RD_RecurringDonations.evaluateRecurringDonationsForNewOppInsert(result);
	    } catch(Exception e) {
            Database.rollback(sp);
            ERR_Handler.processError(e, ERR_Handler_API.Context.RD);
        }    
    }
    public void finish(Database.BatchableContext bc) {
        //update our settings
        npe03__Recurring_Donations_Settings__c rds = UTIL_CustomSettingsFacade.getRecurringDonationsSettings();
        
        AsyncApexJob a = [select CompletedDate from AsyncApexJob where Id = :BC.getJobId()];
                                    
        rds.npe03__Last_Batch_Run__c = a.CompletedDate;
        rds.npe03__Number_of_Successes__c = recCount - failuresCount;
        rds.npe03__Number_of_Failures__c = failuresCount;
        if(!Test.isRunningTest())
            upsert rds;                            
        
        //if needed, send error notifications
        ERR_Notifier.sendErrorNotifications(ERR_Handler_API.Context.RD.name());        
    }
    
    

}