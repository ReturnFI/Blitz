import pymongo
from bson.objectid import ObjectId

class Database:
    def __init__(self, db_name="blitz_panel", collection_name="users"):
        try:
            self.client = pymongo.MongoClient("mongodb://localhost:27017/")
            self.db = self.client[db_name]
            self.collection = self.db[collection_name]
            self.client.server_info()
        except pymongo.errors.ConnectionFailure as e:
            print(f"Could not connect to MongoDB: {e}")
            raise

    def add_user(self, user_data):
        username = user_data.pop('username', None)
        if not username:
            raise ValueError("Username is required")

        if self.collection.find_one({"_id": username.lower()}):
            return None

        user_data['_id'] = username.lower()
        return self.collection.insert_one(user_data)

    def get_user(self, username):
        return self.collection.find_one({"_id": username.lower()})

    def get_all_users(self):
        return list(self.collection.find({}))

    def update_user(self, username, updates):
        return self.collection.update_one({"_id": username.lower()}, {"$set": updates})

    def delete_user(self, username):
        return self.collection.delete_one({"_id": username.lower()})

    def delete_users(self, usernames):
        return self.collection.delete_many({"_id": {"$in": usernames}})

try:
    db = Database()
except pymongo.errors.ConnectionFailure:
    db = None