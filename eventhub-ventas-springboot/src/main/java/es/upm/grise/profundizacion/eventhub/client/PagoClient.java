package es.upm.grise.profundizacion.eventhub.client;

import org.springframework.http.MediaType;
import org.springframework.http.client.ClientHttpRequestFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

@Component
public class PagoClient {

    private final RestClient restClient;

    public PagoClient(ClientHttpRequestFactory requestFactory,
                      @Value("${servicios.pagos.url}") String url) {
        this.restClient = RestClient.builder()
                .baseUrl(url)
                .requestFactory(requestFactory)
                .build();
    }

    public PagoResponse cobrar(PagoRequest peticion) {
        return restClient.post()
                .uri("/api/pagos")
                .contentType(MediaType.APPLICATION_JSON)
                .body(peticion)
                .retrieve()
                .body(PagoResponse.class);
    }
}
