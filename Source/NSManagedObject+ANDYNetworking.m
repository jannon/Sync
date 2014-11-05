//
//  NSManagedObject+ANDYNetworking.m
//
//  Copyright (c) 2014 Elvis Nuñez. All rights reserved.
//

#import "NSManagedObject+ANDYNetworking.h"

#import "NSDictionary+ANDYSafeValue.h"
#import "NSManagedObject+HYPPropertyMapper.h"
#import "NSManagedObject+ANDYMapChanges.h"
#import "ANDYDataManager.h"

@implementation NSManagedObject (ANDYNetworking)

+ (void)andy_processChanges:(NSArray *)changes
            usingEntityName:(NSString *)entityName
                 completion:(void (^)(NSError *error))completion
{
    [self andy_processChanges:changes
              usingEntityName:entityName
                    predicate:nil
                   completion:completion];
}

+ (void)andy_processChanges:(NSArray *)changes
            usingEntityName:(NSString *)entityName
                  predicate:(NSPredicate *)predicate
                 completion:(void (^)(NSError *error))completion
{
    [ANDYDataManager performInBackgroundContext:^(NSManagedObjectContext *context) {
        [self processChanges:changes
             usingEntityName:entityName
                   predicate:predicate
                      parent:nil
                   inContext:context
                  completion:completion];
    }];
}

+ (void)andy_processChanges:(NSArray *)changes
            usingEntityName:(NSString *)entityName
                     parent:(NSManagedObject *)parent
                 completion:(void (^)(NSError *error))completion
{
    [ANDYDataManager performInBackgroundContext:^(NSManagedObjectContext *context) {

        NSManagedObject *safeParent = [parent safeObjectInContext:context];
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"%K = %@", parent.entity.name, safeParent];

        [self processChanges:changes
             usingEntityName:entityName
                   predicate:predicate
                      parent:safeParent
                   inContext:context
                  completion:completion];
    }];
}

+ (void)andy_processChanges:(NSArray *)changes
            usingEntityName:(NSString *)entityName
                  predicate:(NSPredicate *)predicate
                     parent:(NSManagedObject *)parent
                  inContext:(NSManagedObjectContext *)context
                 completion:(void (^)(NSError *error))completion;
{
    [self processChanges:changes
         usingEntityName:entityName
               predicate:predicate
                  parent:parent
               inContext:context
              completion:completion];
}

+ (void)processChanges:(NSArray *)changes
       usingEntityName:(NSString *)entityName
             predicate:(NSPredicate *)predicate
                parent:(NSManagedObject *)parent
             inContext:(NSManagedObjectContext *)context
            completion:(void (^)(NSError *error))completion
{
    [[self class] andy_mapChanges:changes
                   usingPredicate:predicate
                        inContext:context
                    forEntityName:entityName
                         inserted:^(NSDictionary *objectDict) {

                             NSManagedObject *created = [NSEntityDescription insertNewObjectForEntityForName:entityName
                                                                                      inManagedObjectContext:context];
                             [created hyp_fillWithDictionary:objectDict];

                             [created processRelationshipsUsingDictionary:objectDict andParent:parent];

                         } updated:^(NSDictionary *objectDict, NSManagedObject *object) {

                             [object hyp_fillWithDictionary:objectDict];

                         }];

    NSError *error = nil;
    [context save:&error];
    if (error) NSLog(@"ANDYNetworking (error while saving %@): %@", entityName, [error description]);

    if (completion) completion(error);
}

- (void)processRelationshipsUsingDictionary:(NSDictionary *)objectDict
                                  andParent:(NSManagedObject *)parent
{
    NSMutableArray *relationships = [NSMutableArray array];

    for (id propertyDescription in [self.entity properties]) {

        if ([propertyDescription isKindOfClass:[NSRelationshipDescription class]]) {
            [relationships addObject:propertyDescription];
        }
    }

    for (NSRelationshipDescription *relationship in relationships) {
        if (relationship.isToMany) {
            NSArray *childs = [objectDict andy_valueForKey:relationship.name];
            if (!childs) continue;

            NSString *childEntityName = relationship.destinationEntity.name;
            NSString *inverseEntityName = relationship.inverseRelationship.name;
            NSPredicate *childPredicate = [NSPredicate predicateWithFormat:@"%K = %@", inverseEntityName, self];

            [[self class] processChanges:childs
                         usingEntityName:childEntityName
                               predicate:childPredicate
                                  parent:self
                               inContext:self.managedObjectContext
                              completion:nil];
        } else if (parent) {
            [self setValue:parent forKey:relationship.name];
        }
    }
}

#pragma mark - Private Methods

- (NSManagedObject *)safeObjectInContext:(NSManagedObjectContext *)context
{
    NSError *error = nil;
    NSString *entityName = self.entity.name;
    NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:entityName];
    NSString *localKey = [NSString stringWithFormat:@"%@ID", [entityName lowercaseString]];
    request.predicate = [NSPredicate predicateWithFormat:@"%K = %@", localKey, [self valueForKey:localKey]];
    NSArray *objects = [context executeFetchRequest:request error:&error];
    if (error) NSLog(@"parentError: %@", error);
    if (objects.count != 1) abort();
    return [objects firstObject];
}

@end
