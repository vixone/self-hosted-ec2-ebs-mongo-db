package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"time"

	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

// client handles pool of connections to MongoDB
var mongoClient *mongo.Client

func initMongo() {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// TODO: add secure env credentials
	clientOptions := options.Client().
		ApplyURI("mongodb://mongodb:27017").
		SetMaxPoolSize(300)

	client, err := mongo.Connect(ctx, clientOptions)
	if err != nil {
		log.Fatalf("Error connecting to MongoDB: %v", err)
	}

	if err := client.Ping(ctx, nil); err != nil {
		log.Fatalf("Ping failed: %v", err)
	}

	mongoClient = client
	log.Println("Connected to MongoDB")
}

func handler(w http.ResponseWriter, r *http.Request) {
	collection := mongoClient.Database("demo").Collection("test")
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()

	// TODO: add different query handler
	var result map[string]interface{}
	err := collection.FindOne(ctx, map[string]interface{}{"_id": 1}).Decode(&result)
	if err != nil {
		// TODO: Differentiate between 404 and 500 errors.
		http.Error(w, "Error fetching data", http.StatusInternalServerError)
		return
	}

	fmt.Fprintf(w, "Fetched document: %+v", result)
}

func main() {
	initMongo()
	defer func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		mongoClient.Disconnect(ctx)
	}()

	http.HandleFunc("/", handler)
	log.Println("Go Wrapper Service running on :8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
}
