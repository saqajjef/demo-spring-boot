package com.demo.demo;


import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

@RestController
@RequestMapping("/api")
public class ApiController {

    private final WebClient webClient = WebClient.create("https://jsonplaceholder.typicode.com");

    @GetMapping("/posts")
    public Flux<Object> getPostList() {
        return webClient.get()
                .uri("/posts")
                .retrieve()
                .bodyToFlux(Object.class);
    }

    @GetMapping("/todo")
    public Mono<String> getTodo() {
        return webClient.get()
                .uri("/todos/1")
                .retrieve()
                .bodyToMono(String.class);
    }

    @GetMapping("/photos")
    public Flux<Object> getPhotos() {
        return webClient.get()
                .uri("/photos")
                .retrieve()
                .bodyToFlux(Object.class);
    }
}
